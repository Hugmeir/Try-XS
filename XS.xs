#define PERL_NO_GET_CONTEXT 1
#ifdef WIN32
#  define NO_XSLOCKS
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

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

STATIC OP*
S_pp_catch(pTHX)
{
    dVAR;
    sv_setsv(GvSV(PL_defgv), GvSV(PL_errgv));
    FREETMPS;
    LEAVE;
    sv_setsv(GvSV(PL_errgv)mGvSV(PL_defgv), );
    return cLOGOP->op_next;
}

STATIC OP*
S_pp_entertry(pTHX)
{
    OP * try = PL_op;
    ENTER;
    SAVETMPS;
    SAVEGENERICSV(GvSV(PL_errgv));

    OP * op = PL_ppaddr[OP_ENTERTRY](aTHX);
    PL_op = op;
    while ((PL_op = op = op->op_ppaddr(aTHX))) {
        if (op->op_ppaddr == S_pp_catch) {
            sv_dump(GvSV(PL_errgv));
            op = cLOGOP->op_other;
            break;
        }
    }
    FREETMPS;
    LEAVE;
    return op;
}

static OP *
S_ck_try(pTHX_ OP *entersubop, GV *namegv, SV *cv)
{
    OP * leavetry = remove_sub_call(entersubop);
    OP * entertry = cUNOPx(leavetry)->op_first;
    OP * catch    = leavetry->op_sibling;
      
    PERL_UNUSED_ARG(namegv);
    PERL_UNUSED_ARG(cv);      
      
    entertry->op_type   = OP_CUSTOM;
    entertry->op_ppaddr = S_pp_entertry;

    return leavetry;
}

STATIC OP*
S_parse_try(pTHX_ GV* namegv, SV* psobj, U32* flagsp) {
    OP* evalop;
    OP* blockop;
    OP* rest;
 
    PERL_UNUSED_ARG(namegv);
    PERL_UNUSED_ARG(psobj);
 
    blockop = parse_block(0);
   
    if (!blockop)
       croak("Couldn't parse the try {} block");
   
    evalop = newUNOP(OP_ENTERTRY, 0, blockop);
   
    /* XXX ffs broken */
    rest = parse_args_list(flagsp);
    if (rest) {
        if ( rest->op_type != OP_LIST )
            rest = newLISTOP(OP_LIST, 0, rest, NULL);
        OP* p = cUNOPx(rest)->op_first;
    
        evalop->op_sibling = p->op_sibling;
        p->op_sibling = evalop;
    }
    else {
        rest = evalop;
    }

    return rest;
}


static OP *
S_ck_catch(pTHX_ OP *entersubop, GV *namegv, SV *cv)
{
    OP * catch = remove_sub_call(entersubop);

    PERL_UNUSED_ARG(namegv);
    PERL_UNUSED_ARG(cv);

    return catch;
}

STATIC OP*
S_parse_catch(pTHX_ GV* namegv, SV* psobj, U32* flagsp) {
    OP* condop;
    OP* blockop;
    OP* rest;
 
    PERL_UNUSED_ARG(namegv);
    PERL_UNUSED_ARG(psobj);
 
    blockop = parse_block(0);
   
    if (!blockop)
       croak("Couldn't parse the try {} block");

    condop = newCONDOP(0, newOP(OP_NULL, 0), newOP(OP_NULL, 0), blockop);
    cUNOPx(condop)->op_first->op_type   = OP_CUSTOM;
    cUNOPx(condop)->op_first->op_ppaddr = S_pp_catch;

    /* XXX ffs broken */
    rest = parse_args_list(flagsp);
    if (rest) {
        if ( rest->op_type != OP_LIST )
            rest = newLISTOP(OP_LIST, 0, rest, NULL);
        OP* p = cUNOPx(rest)->op_first;
    
        condop->op_sibling = p->op_sibling;
        p->op_sibling = condop;
    }
    else {
        rest = condop;
    }

    return rest;
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
    croak("Don't do that.");

void
catch(block, ...)
PROTOTYPE: &;@
PPCODE:
    croak("Don't do that.");


BOOT:
{
    CV * const try     = get_cvn_flags("Try::XS::try", 12, 0);
    CV * const catch   = get_cvn_flags("Try::XS::catch", 14, 0);
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
    cv_set_call_checker(catch, S_ck_catch, &PL_sv_undef);
    cv_set_call_parser(catch, S_parse_catch, &PL_sv_undef);
}
