; htasc - set the hi bit on the last byte of a string for termination
; (by Tom Greene)
.macro htasc str
	.repeat	.strlen(str)-1,I
		.byte	.strat(str,I)
	.endrep
	.byte	.strat(str,.strlen(str)-1) | $80
.endmacro

; For every token, a byte gets put into segment "DUMMY".
; This way, we count up with every token. The DUMMY segment
; doesn't get linked into the binary.
.macro init_token_tables
        .segment "VECTORS"
TOKEN_ADDRESS_TABLE:
        .segment "KEYWORDS"
TOKEN_NAME_TABLE:
		.segment "DUMMY"
DUMMY_START:
.endmacro

; optionally define token symbol
; count up token number
.macro define_token token
        .segment "DUMMY"
		.ifnblank token
			token := <(*-DUMMY_START)+$80
		.endif
		.res 1; count up in any case
.endmacro

; lay down a keyword, optionally define a token symbol
.macro keyword key, token
		.segment "KEYWORDS"
		htasc	key
		define_token token
.endmacro

; lay down a keyword and an address (RTS style),
; optionally define a token symbol
.macro keyword_rts key, vec, token
        .segment "VECTORS"
		.word	vec-1
		keyword key, token
.endmacro

; lay down a keyword and an address,
; optionally define a token symbol
.macro keyword_addr key, vec, token
        .segment "VECTORS"
		.addr	vec
		keyword key, token
.endmacro

.macro count_tokens
        .segment "DUMMY"
		NUM_TOKENS := <(*-DUMMY_START)
.endmacro

; ----------------------------------------------------------------------------
; Extension keyword tables (two-byte tokens: TOKEN_EXT prefix + subtoken).
; A parallel name table (EXT_NAME_TABLE) and RTS-style address table
; (EXT_ADDRESS_TABLE) live in their own segments so each has its own 256-byte /
; 128-entry budget, independent of the full primary tables. ext_keyword_rts
; appends to both in lockstep, so extension index N indexes both tables. See
; the tokenizer (TOKENIZE_EXT), dispatch (EXECUTE_STATEMENT1 @ext) and LIST
; hooks in program.s / flow1.s.
.macro init_ext_token_tables
        .segment "EXTVEC"
EXT_ADDRESS_TABLE:
        .segment "EXTKEYW"
EXT_NAME_TABLE:
.endmacro

.macro ext_keyword_rts key, vec
        .segment "EXTVEC"
		.word	vec-1
        .segment "EXTKEYW"
		htasc	key
.endmacro

.macro end_ext_token_tables
        .segment "EXTKEYW"
		.byte	0                       ; name-table terminator
EXT_NAME_TABLE_END:
        .segment "EXTVEC"
EXT_ADDRESS_TABLE_END:
		; Both extension tables are indexed with an 8-bit register, exactly like
		; the primary tables, so each must stay within its own budget.
		NUM_EXT_TOKENS = <((EXT_ADDRESS_TABLE_END - EXT_ADDRESS_TABLE) / 2)
		.assert (EXT_NAME_TABLE_END - EXT_NAME_TABLE) <= 256, error, "extension keyword name table exceeds 256 bytes"
		.assert (EXT_ADDRESS_TABLE_END - EXT_ADDRESS_TABLE) <= 256, error, "extension address table exceeds 128 entries"
.endmacro

; ----------------------------------------------------------------------------
; Extension FUNCTION keyword tables (two-byte tokens: TOKEN_EXTFN prefix +
; subtoken). Same shape as the extension statement tables above, but the
; address table holds a plain .addr (like keyword_addr/UNFNC), not an RTS-style
; vec-1, because dispatch (EXTFN_DISPATCH in clementina_extra.s) calls it with a
; plain jsr, mirroring how UNARY calls primary functions. See TOKENIZE_EXTFN
; (program.s), the LIST detokenizer (program.s), and eval.s's dispatch hook.
; ----------------------------------------------------------------------------
.macro init_extfn_token_tables
        .segment "EXTFNVEC"
EXTFN_ADDRESS_TABLE:
        .segment "EXTFNKEYW"
EXTFN_NAME_TABLE:
.endmacro

.macro extfn_keyword_addr key, vec
        .segment "EXTFNVEC"
		.addr	vec
        .segment "EXTFNKEYW"
		htasc	key
.endmacro

.macro end_extfn_token_tables
        .segment "EXTFNKEYW"
		.byte	0                       ; name-table terminator
EXTFN_NAME_TABLE_END:
        .segment "EXTFNVEC"
EXTFN_ADDRESS_TABLE_END:
		NUM_EXTFN_TOKENS = <((EXTFN_ADDRESS_TABLE_END - EXTFN_ADDRESS_TABLE) / 2)
		.assert (EXTFN_NAME_TABLE_END - EXTFN_NAME_TABLE) <= 256, error, "extension function keyword name table exceeds 256 bytes"
		.assert (EXTFN_ADDRESS_TABLE_END - EXTFN_ADDRESS_TABLE) <= 256, error, "extension function address table exceeds 128 entries"
.endmacro

.macro init_error_table
        .segment "ERROR"
ERROR_MESSAGES:
.endmacro

.macro define_error error, msg
        .segment "ERROR"
		error := <(*-ERROR_MESSAGES)
		htasc msg
.endmacro

;---------------------------------------------
; set the MSB of every byte of a string
.macro asc80 str
	.repeat	.strlen(str),I
		.byte	.strat(str,I)+$80
	.endrep
.endmacro

