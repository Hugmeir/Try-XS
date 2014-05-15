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
S_pp_try(pTHX)
{
    return NORMAL;
}

static OP *
S_ck_try(pTHX_ OP *entersubop, GV *namegv, SV *cv)
{
    OP * eval  = remove_sub_call(entersubop);
    OP * catch = eval->op_sibling;
    if ( !catch || 0 /*catch->op_ppaddr != S_pp_catch*/)
        return eval;
    return eval;
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

#ifdef XopENTRY_set
static XOP my_xop;
#endif

MODULE = Try::XS		PACKAGE = Try::XS		

PROTOTYPES: ENABLE

void
try(block, ...)
PROTOTYPE: &;@
PPCODE:
    croak("Don't do that.");

BOOT:
{
    CV * const try     = get_cvn_flags("Try::XS::try", 12, 0);
    /*
    CV * const catch   = get_cvn_flags("Try::XS::catch", 14, 0);
    CV * const finally = get_cvn_flags("Try::XS::finally", 16, 0);
*/
    cv_set_call_checker(try, S_ck_try, &PL_sv_undef);
    cv_set_call_parser(try, S_parse_try, &PL_sv_undef);
#ifdef XopENTRY_set
    XopENTRY_set(&my_xop, xop_name, "try");
    XopENTRY_set(&my_xop, xop_desc, "try");
    XopENTRY_set(&my_xop, xop_class, OA_UNOP);
    Perl_custom_op_register(aTHX_ S_pp_try, &my_xop);
#endif /* XopENTRY_set */
}
