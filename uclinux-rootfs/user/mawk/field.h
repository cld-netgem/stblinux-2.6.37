/********************************************
field.h
copyright 1991, Michael D. Brennan

This is a source file for mawk, an implementation of
the AWK programming language.

Mawk is distributed without warranty under the terms of
the GNU General Public License, version 2, 1991.
********************************************/

/*
 * $MawkId: field.h,v 1.8 2010/05/07 22:03:31 tom Exp $
 * @Log: field.h,v @
 * Revision 1.2  1995/06/18  19:42:16  mike
 * Remove some redundant declarations and add some prototypes
 *
 * Revision 1.1.1.1  1993/07/03  18:58:12  mike
 * move source to cvs
 *
 * Revision 5.2  1992/01/06  08:10:24  brennan
 * set_binmode() proto for MSDOS
 *
 * Revision 5.1  91/12/05  07:59:16  brennan
 * 1.1 pre-release
 * 
 */

/* field.h */

#ifndef  MAWK_FIELD_H
#define  MAWK_FIELD_H   1

#include "nstd.h"
#include "types.h"

void set_field0(char *, size_t);
void split_field0(void);
size_t space_split(char *, size_t);
size_t re_split(STRING *, PTR);
size_t null_split(char *, size_t);
void field_assign(CELL *, CELL *);
char *is_string_split(PTR, unsigned *);
void slow_cell_assign(CELL *, CELL *);
CELL *slow_field_ptr(int);
int field_addr_to_index(CELL *);
void set_binmode(int);

#define  NUM_PFIELDS		5
extern CELL field[FBANK_SZ + NUM_PFIELDS];
	/* $0, $1 ... $(MAX_SPLIT), NF, RS, RS, CONVFMT, OFMT */

/* more fields if needed go here */
extern CELL *fbank[NUM_FBANK];	/* fbank[0] == field */

/* index to CELL *  for a field */
#define field_ptr(i) ((i) <= MAX_SPLIT ? field + (i) : slow_field_ptr(i))

/* some, such as RS may be defined in system-headers */
#undef NF
#undef RS
#undef FS
#undef CONVFMT
#undef OFMT

/* the pseudo fields, assignment has side effects */
#define  NF       (field + MAX_SPLIT + 1)	/* must be first */
#define  RS       (field + MAX_SPLIT + 2)
#define  FS       (field + MAX_SPLIT + 3)
#define  CONVFMT  (field + MAX_SPLIT + 4)
#define  OFMT     (field + MAX_SPLIT + 5)	/* must be last */

#define  LAST_PFIELD	OFMT

/* some compilers choke on (NF-field) in a case statement
   even though it's constant so ...
*/
#define  NF_field    (MAX_SPLIT+1)
#define  RS_field    (MAX_SPLIT+2)
#define  FS_field    (MAX_SPLIT+3)
#define  CONVFMT_field (MAX_SPLIT+4)
#define  OFMT_field  (MAX_SPLIT+5)

extern int nf;			/* shadows NF */

/* a shadow type for RS and FS */
#define  SEP_SPACE      0
#define  SEP_CHAR       1
#define  SEP_STR        2
#define  SEP_RE         3
#define  SEP_MLR	4

typedef struct {
    char type;
    char c;
    PTR ptr;			/* STRING* or RE machine* */
} SEPARATOR;

extern SEPARATOR rs_shadow;
extern CELL fs_shadow;

/*  types for splitting overflow */

typedef struct spov {
    struct spov *link;
    STRING *sval;
} SPLIT_OV;

extern SPLIT_OV *split_ov_list;

#endif /* MAWK_FIELD_H  */
