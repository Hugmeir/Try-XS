#define PERL_NO_GET_CONTEXT 1
#ifdef WIN32
#  define NO_XSLOCKS
#endif
#include "EXTERN.h"
#include "perl.h"

#ifndef WIN32
#define PERL_CORE
#include "XSUB.h"
#else
#include "XSUB.h"
#endif

#if (PERL_REVISION == 5 && PERL_VERSION < 14)
#include "callchecker0.h"
#endif

#include "callparser1.h"

STATIC OP* remove_sub_call(pTHX_ OP* entersubop) {
#define remove_sub_call(a) remove_sub_call(aTHX_ a)
   OP* aop;
   OP* pushop;
   OP* realop;
 
   pushop = cUNOPx(entersubop)->op_first;
   if (!pushop->op_sibling)
      pushop = cUNOPx(pushop)->op_first;
 
   aop = pushop;
   realop = pushop->op_sibling;
   if (!realop || !realop->op_sibling)
      croak("Don't do that");
 
   for (; aop->op_sibling->op_sibling; aop = aop->op_sibling) {}
 
   pushop->op_sibling = aop->op_sibling;
   aop->op_sibling = NULL;
   op_free(entersubop);

   return realop;
}

#define MY_SAVESV(gv)   STMT_START { \
    SV *tmp = newSVsv(GvSV(gv)); \
    save_gp(gv, 0);   \
    GvINTRO_off(gv);  \
    SAVEGENERICSV(GvSV(gv)); \
    GvSV(gv) = tmp;\
} STMT_END

STATIC OP*
S_pp_catch(pTHX)
{
    dVAR;
    /* First, save the exception in tmp */
    SV *tmp = newSVsv(GvSVn(PL_errgv));
    LEAVE;
    
    /* Run the OP_ENTER for the catch {} */
    OP *next = PL_op = cLOGOP->op_other;
    PL_op = next = next->op_ppaddr(aTHX);

    MY_SAVESV(PL_defgv);

    /* Now that we're in here, replace $_ and @_ */
    sv_setsv(GvSV(PL_defgv), tmp);
    
    GvAV(PL_defgv) = NULL;
    
    av_push(GvAVn(PL_defgv), tmp);
    
    return next;
}

STATIC OP*
S_pp_entertry(pTHX)
{
    /* Preserve the original $@ inside the try {} */
    OP * op;
    SV * tmp = newSVsv(GvSVn(PL_errgv));
    PL_op = op = PL_ppaddr[OP_ENTERTRY](aTHX);

    sv_setsv(GvSVn(PL_errgv), tmp);

    while ((PL_op = op = op->op_ppaddr(aTHX))) {
        if (op->op_ppaddr == S_pp_catch) {
            op = cLOGOP->op_next;
            break;
        }
    }
    return op;
}

/* The try { ... } ... is wrapped in an implicit
 * do {} block, which we use to protect $@ from
 * being overwritten
 * So basially, this is our do { local $@ = $@; ... }
 */
STATIC OP*
S_pp_tryscope(pTHX)
{
    OP *next = PL_ppaddr[OP_ENTER](aTHX);
    /* Protect $@, but maintain its original value */
    save_aptr(&GvAV(PL_defgv));
    MY_SAVESV(PL_errgv);
    GvAV(PL_defgv) = NULL;
    return next;
}

static OP *
S_ck_try(pTHX_ OP *entersubop, GV *namegv, SV *cv)
{
    OP * leavetry = remove_sub_call(entersubop);
    
    PERL_UNUSED_ARG(namegv);
    PERL_UNUSED_ARG(cv);      
      
    return leavetry;
}

#define peek_next_token(l, len) STMT_START {    \
    c = lex_peek_unichar(LEX_KEEP_PREVIOUS);    \
    if ( c == l ) {                             \
        bufend = PL_parser->bufend;             \
        bufptr = PL_parser->bufptr;             \
        if ( (bufend - bufptr) < len ) {        \
            lex_next_chunk(LEX_KEEP_PREVIOUS);  \
            bufend = PL_parser->bufend;         \
            bufptr = PL_parser->bufptr;         \
        }                                       \
    }                                           \
} STMT_END

STATIC OP*
S_ck_noret(pTHX_ OP* o)
{
    warn("Dubious use of return() in catch/finally");
    return o;
}

STATIC OP*
S_parse_try(pTHX_ GV* namegv, SV* psobj, U32* flagsp) {
    OP* evalop;
    OP* blockop;
    OP* catch = NULL;
    OP* finally = NULL;
    I32 c = lex_peek_unichar(LEX_KEEP_PREVIOUS);
    
    PERL_UNUSED_ARG(namegv);
    PERL_UNUSED_ARG(psobj);
 
    lex_read_space(0);
    c = lex_peek_unichar(LEX_KEEP_PREVIOUS);
    
    if ( c == '(' ) {
        croak("syntax error, are you trying to call try {...} as try({...})?");
    }
    
    blockop = parse_block(0);
   
    if (!blockop)
       croak("Couldn't parse the try {} block");

    evalop = newUNOP(OP_ENTERTRY, 0, blockop);
    
    OP *entertry = cUNOPx(evalop)->op_first;
   
    entertry->op_type   = OP_CUSTOM;
    entertry->op_ppaddr = S_pp_entertry;

    /* Do we have any more arguments? */
    lex_read_space(0);
    c = lex_peek_unichar(LEX_KEEP_PREVIOUS);
    
    bool good = TRUE;
    while ( (c == 'c' || c == 'f') && good ) {
        char * bufend;
        char * bufptr;

        switch (c) {
        case 'c': {
            peek_next_token('c', 7);
            if ( (bufend - bufptr) >= 5
                && memEQ(bufptr, "catch", 5)
                && (!*(bufptr + 5)
                    || isSPACE(*(bufptr+5))
                    || *(bufptr + 5) == '{'
                   )
                )
            {
                OP * catchblock;
                
                if ( catch ) {
                    croak("A try { ... } may not be followed by multiple catch { ... } blocks");
                }
                
                lex_read_to(PL_parser->bufptr+5);
            
                lex_read_space(0);
            
                OP *(*nxck_return)(pTHX_ OP *o) = PL_check[OP_RETURN]; 

                PL_check[OP_RETURN] = S_ck_noret;
                catchblock = parse_block(0);
                PL_check[OP_RETURN] = nxck_return;

                lex_read_space(0);

                catch = op_prepend_elem(OP_LINESEQ, newOP(OP_ENTER, 0), catchblock);
                catch->op_type = OP_LEAVE;
                catch->op_ppaddr = PL_ppaddr[OP_LEAVE];
                c = lex_peek_unichar(LEX_KEEP_PREVIOUS);
            }
            break;
        }
        case 'f': {
        peek_next_token('f', 9);

            while ( c == 'f'
                && (bufend - bufptr) >= 7
                && memEQ(bufptr, "finally", 7)
                && (!*(bufptr + 7)
                    || isSPACE(*(bufptr+7))
                    || *(bufptr + 7) == '{'
                   )
                )
            {
                OP * finallyblock;
                lex_read_to(PL_parser->bufptr+7);
                lex_read_space(0);
            
                OP *(*nxck_return)(pTHX_ OP *o) = PL_check[OP_RETURN]; 

                PL_check[OP_RETURN] = S_ck_noret;
                finallyblock = parse_block(0);
                PL_check[OP_RETURN] = nxck_return;

                finallyblock = op_prepend_elem(OP_LINESEQ, newOP(OP_ENTER, 0), finallyblock);
                finallyblock->op_type = OP_LEAVE;
                finallyblock->op_ppaddr = PL_ppaddr[OP_LEAVE];
            
                if ( !finally ) {
                    finally = newLISTOP(OP_LIST, 0, finallyblock, NULL);
                }
                else {
                    op_append_elem(OP_LIST, finally, finallyblock);
                }
            
                lex_read_space(0);
                peek_next_token('f', 9);
            }
            break;
        }
        default:
            good = FALSE;
            break;
        }
    }

    if ( finally ) {
        finally = op_prepend_elem(OP_LINESEQ, newOP(OP_ENTER, 0), finally);
        finally->op_type = OP_LEAVE;
        finally->op_ppaddr = PL_ppaddr[OP_LEAVE];
        op_contextualize(finally, G_VOID);
    }

    /* No catch */
    if (!catch) {
        /* Attach the finallies */
        if (finally) {
            evalop = op_append_elem(OP_LIST, evalop, finally);
        }
        OP *o = op_prepend_elem(OP_LINESEQ, newOP(OP_ENTER, 0), evalop);
        o->op_type = OP_LEAVE;
        o->op_ppaddr = PL_ppaddr[OP_LEAVE];
        cUNOPx(o)->op_first->op_type   = OP_CUSTOM;
        cUNOPx(o)->op_first->op_ppaddr = S_pp_tryscope;
        return o;
    }
    
    LOGOP *logop;
    NewOp(1101, logop, 1, LOGOP);

    logop->op_type = (OPCODE)OP_OR;
    logop->op_ppaddr = PL_ppaddr[OP_OR];
    logop->op_first = evalop;
    logop->op_flags = (U8)(0 | OPf_KIDS);
    logop->op_other = LINKLIST(catch);
    logop->op_private = (U8)(1 | (0 >> 8));

    /* establish postfix order */
    logop->op_next = LINKLIST(evalop);
    evalop->op_next = (OP*)logop;
    evalop->op_sibling = catch;

    OP * or_op = newUNOP(OP_NULL, 0, (OP*)logop);
    catch->op_next = or_op;
   
    OP *orop = cUNOPx(or_op)->op_first;
    orop->op_type   = OP_CUSTOM;
    orop->op_ppaddr = S_pp_catch;
    
    /* Attach the finallies */
    or_op = op_append_elem(OP_LIST, or_op, finally);
    
    OP *o = op_prepend_elem(OP_LINESEQ, newOP(OP_ENTER, 0), or_op);
    o->op_type = OP_LEAVE;
    o->op_ppaddr = PL_ppaddr[OP_LEAVE];
    cUNOPx(o)->op_first->op_type   = OP_CUSTOM;
    cUNOPx(o)->op_first->op_ppaddr = S_pp_tryscope;

    return o;
}


static OP *
S_ck_bad(pTHX_ OP *entersubop, GV *namegv, SV *sv)
{
    PERL_UNUSED_ARG(entersubop);
    PERL_UNUSED_ARG(sv);
    
    croak("Useless bare %s { ... }", GvNAME(namegv));

    return entersubop;
}

#ifdef XopENTRY_set
static XOP entertry_op, catch_op, finally_op;
#endif

MODULE = Try::XS		PACKAGE = Try::XS		

PROTOTYPES: ENABLE

void
try(block, ...)
PROTOTYPE: &;@
PPCODE:
    croak("Attempting to call try() directly is not support");

void
catch(...)
PROTOTYPE: &;@
PPCODE:
    croak("Attempting to call catch() directly is not support");

void
finally(...)
PROTOTYPE: &;@
PPCODE:
    croak("Attempting to call finally() directly is not support");

BOOT:
{
    CV * const try     = get_cvn_flags("Try::XS::try", 12, 0);
    CV * const catch   = get_cvn_flags("Try::XS::catch", 14, 0);
    CV * const finally = get_cvn_flags("Try::XS::finally", 16, 0);
#ifdef XopENTRY_set
    XopENTRY_set(&entertry_op, xop_name, "entertry");
    XopENTRY_set(&entertry_op, xop_desc, "entertry");
    XopENTRY_set(&entertry_op, xop_class, OA_UNOP);
    Perl_custom_op_register(aTHX_ S_pp_entertry, &entertry_op);
    XopENTRY_set(&catch_op, xop_name, "catch");
    XopENTRY_set(&catch_op, xop_desc, "catch");
    XopENTRY_set(&catch_op, xop_class, OA_UNOP);
    Perl_custom_op_register(aTHX_ S_pp_catch, &catch_op);
#endif /* XopENTRY_set */
    cv_set_call_checker(try, S_ck_try, &PL_sv_undef);
    cv_set_call_parser(try, S_parse_try, &PL_sv_undef);

    cv_set_call_checker(finally, S_ck_bad, &PL_sv_undef);
    cv_set_call_checker(catch, S_ck_bad, &PL_sv_undef);
}
