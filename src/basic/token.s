		init_token_tables

		keyword_rts "END", END
		keyword_rts "FOR", FOR, TOKEN_FOR
		keyword_rts "NEXT", NEXT
		keyword_rts "DATA", DATA
.ifdef CONFIG_FILE
		keyword_rts "INPUT#", INPUTH
.endif
		keyword_rts "INPUT", INPUT, TOKEN_INPUT
		keyword_rts "DIM", DIM
		keyword_rts "READ", READ
.ifdef APPLE
		keyword_rts "PLT", PLT
.else
		keyword_rts "LET", LET
.endif
		keyword_rts "GOTO", GOTO, TOKEN_GOTO
		keyword_rts "RUN", RUN
		keyword_rts "IF", IF
		keyword_rts "RESTORE", RESTORE
		keyword_rts "GOSUB", GOSUB, TOKEN_GOSUB
		keyword_rts "RETURN", POP
.ifdef APPLE
		keyword_rts "TEX", TEX, TOKEN_REM
.else
		keyword_rts "REM", REM, TOKEN_REM
.endif
		keyword_rts "STOP", STOP
		keyword_rts "ON", ON
.ifdef CONFIG_NULL
		keyword_rts "NULL", NULL
.endif
.ifdef KBD
		keyword_rts "PLOD", PLOD
		keyword_rts "PSAV", PSAV
		keyword_rts "VLOD", VLOD
		keyword_rts "VSAV", VSAV
.endif
.ifndef CONFIG_NO_POKE
		keyword_rts "WAIT", WAIT
.endif
.ifndef KBD
		keyword_rts "LOAD", LOAD
		keyword_rts "SAVE", SAVE
.endif
.ifdef CONFIG_CBM_ALL
		keyword_rts "VERIFY", VERIFY
.endif
		keyword_rts "DEF", DEF
.ifdef KBD
		keyword_rts "SLOD", SLOD
.endif
.ifndef CONFIG_NO_POKE
		keyword_rts "POKE", POKE
.endif
.ifdef CLEMENTINA
		; Keyword names must stay SHORT: the tokenizer indexes this name table
		; with an 8-bit Y register, so every name plus the trailing $00 must fit
		; in 256 bytes. Overflowing it makes the keyword search never find the
		; terminator and hang on every typed line. (CRSR=cursor position x,y.)
		keyword_rts "COLOR", BASIC_COLOR
		keyword_rts "FLIPX", BASIC_FLIPX
		keyword_rts "FLIPY", BASIC_FLIPY
		keyword_rts "ALT", BASIC_ALT
		keyword_rts "STYLE", BASIC_STYLE
		keyword_rts "CRSR", BASIC_CRSR
		keyword_rts "CLS", BASIC_CLS
.endif
.ifdef CONFIG_FILE
		keyword_rts "PRINT#", PRINTH
.endif
		keyword_rts "PRINT", PRINT, TOKEN_PRINT
		keyword_rts "CONT", CONT
		keyword_rts "LIST", LIST
.ifdef CONFIG_CBM_ALL
		keyword_rts "CLR", CLEAR
.else
		keyword_rts "CLEAR", CLEAR
.endif
.ifdef CONFIG_FILE
		keyword_rts "CMD", CMD
		keyword_rts "SYS", SYS
		keyword_rts "OPEN", OPEN
		keyword_rts "CLOSE", CLOSE
.endif
.ifndef CONFIG_SMALL
		keyword_rts "GET", GET
.endif
.ifdef KBD
		keyword_rts "PRT", PRT
.endif
		keyword_rts "NEW", NEW

		count_tokens

		keyword	"TAB(", TOKEN_TAB
		keyword	"TO", TOKEN_TO
		keyword	"FN", TOKEN_FN
		keyword	"SPC(", TOKEN_SPC
		keyword	"THEN", TOKEN_THEN
		keyword	"NOT", TOKEN_NOT
		keyword	"STEP", TOKEN_STEP
		keyword	"+", TOKEN_PLUS
		keyword	"-", TOKEN_MINUS
		keyword	"*"
		keyword	"/"
.ifdef KBD
		keyword	"#"
.else
		keyword	"^"
.endif
		keyword	"AND"
		keyword	"OR"
		keyword	">", TOKEN_GREATER
		keyword	"=", TOKEN_EQUAL
		keyword	"<"

        .segment "VECTORS"
UNFNC:

		keyword_addr "SGN", SGN, TOKEN_SGN
		keyword_addr "INT", INT
		keyword_addr "ABS", ABS
.ifdef KBD
		keyword_addr "VER", VER
.endif
.ifndef CONFIG_NO_POKE
  .ifdef CONFIG_RAM
		keyword_addr "USR", IQERR
  .else
		keyword_addr "USR", USR, TOKEN_USR
  .endif
.endif
		keyword_addr "FRE", FRE
		keyword_addr "POS", POS
		keyword_addr "SQR", SQR
		keyword_addr "RND", RND
		keyword_addr "LOG", LOG
		keyword_addr "EXP", EXP
.segment "VECTORS"
UNFNC_COS:
		keyword_addr "COS", COS
.segment "VECTORS"
UNFNC_SIN:
		keyword_addr "SIN", SIN
.segment "VECTORS"
UNFNC_TAN:
		keyword_addr "TAN", TAN
.segment "VECTORS"
UNFNC_ATN:
		keyword_addr "ATN", ATN
.ifdef KBD
		keyword_addr "GETC", GETC
.endif
.ifndef CONFIG_NO_POKE
		keyword_addr "PEEK", PEEK
.endif
		keyword_addr "LEN", LEN
		keyword_addr "STR$", STR
		keyword_addr "VAL", VAL
		keyword_addr "ASC", ASC
		keyword_addr "CHR$", CHRSTR
		keyword_addr "LEFT$", LEFTSTR, TOKEN_LEFTSTR
		keyword_addr "RIGHT$", RIGHTSTR
		keyword_addr "MID$", MIDSTR
.ifdef CONFIG_2
		keyword	"GO", TOKEN_GO
.endif
        .segment "KEYWORDS"
		.byte   0

		; The tokenizer (PARSE_INPUT_LINE in program.s) walks this name table
		; with an 8-bit Y index, so the terminator must sit at offset <= 255 or
		; the keyword search never ends and hangs on every typed line. Guard it
		; at build time: shorten keyword names if this fails.
		.assert (* - TOKEN_NAME_TABLE) <= 256, error, "BASIC keyword name table exceeds 256 bytes (8-bit tokenizer index)"

        .segment "VECTORS"
MATHTBL:
        .byte   $79
        .word   FADDT-1
        .byte   $79
        .word   FSUBT-1
        .byte   $7B
        .word   FMULTT-1
        .byte   $7B
        .word   FDIVT-1
        .byte   $7F
        .word   FPWRT-1
        .byte   $50
        .word   TAND-1
        .byte   $46
        .word   OR-1
        .byte   $7D
        .word   NEGOP-1
        .byte   $5A
        .word   EQUOP-1
        .byte   $64
        .word   RELOPS-1

.ifdef CLEMENTINA
; ----------------------------------------------------------------------------
; Extension keyword table (two-byte tokens). The cruncher emits TOKEN_EXT ($FF)
; followed by a subtoken ($80|index) for these keywords, so they cost nothing in
; the full 256-byte primary name table above and dodge the 128 single-byte token
; limit. Each extension table has its own 256-byte / 128-entry budget. Add new
; sprite/sound/etc. statements here; the tokenizer (TOKENIZE_EXT), statement
; dispatch (EXECUTE_STATEMENT1 @ext) and LIST detokenizer in program.s/flow1.s
; handle the prefix generically, so no other code changes are needed per command.
; Handlers live in clementina_extra.s (EXTRA segment).
; ----------------------------------------------------------------------------
        init_ext_token_tables
        ext_keyword_rts "BCOLOR", BASIC_BCOLOR
        ; Sound: MIA 4-voice PSG control (see clementina-mia docs/audio.md and
        ; src/basic/CLEMENTINA.md). None of these names is a prefix of another,
        ; so table order is free; TOKENIZE_EXT runs before the primary table so
        ; NOTE/FREQ/WAVE do not collide with NOT/FRE/WAIT.
        ext_keyword_rts "SNDON",  BASIC_SNDON
        ext_keyword_rts "SNDOFF", BASIC_SNDOFF
        ext_keyword_rts "SNDCLR", BASIC_SNDCLR
        ext_keyword_rts "VOL",    BASIC_VOL
        ext_keyword_rts "WAVE",   BASIC_WAVE
        ext_keyword_rts "NOTE",   BASIC_NOTE
        ext_keyword_rts "FREQ",   BASIC_FREQ
        ext_keyword_rts "GATE",   BASIC_GATE
        ext_keyword_rts "ADSR",   BASIC_ADSR
        ext_keyword_rts "PULSE",  BASIC_PULSE
        ext_keyword_rts "PAN",    BASIC_PAN
        ext_keyword_rts "PLAY",   BASIC_PLAY
        ; Video Phase 1 (see docs/basic-video.md): background/sprite layer,
        ; CHR bank, and palette control. Direct register wrappers, same shape
        ; as BCOLOR/the sound statements above; handlers in clementina_extra.s.
        ext_keyword_rts "BGON",     BASIC_BGON
        ext_keyword_rts "BGOFF",    BASIC_BGOFF
        ext_keyword_rts "BGMODE",   BASIC_BGMODE
        ext_keyword_rts "BGSET",    BASIC_BGSET
        ext_keyword_rts "SCROLL",   BASIC_SCROLL
        ext_keyword_rts "BGBANK",   BASIC_BGBANK
        ext_keyword_rts "BGALT",    BASIC_BGALT
        ext_keyword_rts "SPRON",    BASIC_SPRON
        ext_keyword_rts "SPROFF",   BASIC_SPROFF
        ext_keyword_rts "SPRCOUNT", BASIC_SPRCOUNT
        ext_keyword_rts "SPRBANK",  BASIC_SPRBANK
        ext_keyword_rts "CHRMODE",  BASIC_CHRMODE
        ext_keyword_rts "CHRPLANE", BASIC_CHRPLANE
        ext_keyword_rts "PALETTE",  BASIC_PALETTE
        ext_keyword_rts "VIDON",    BASIC_VIDON
        ext_keyword_rts "VIDOFF",   BASIC_VIDOFF
        ; Video Phase 2: bulk loading from DATA + full sprite setup.
        ext_keyword_rts "BGCHAR",   BASIC_BGCHAR
        ; CHRLOAD/PALLOAD/OAMLOAD keep their original names and slots here
        ; (this table already had exactly enough room for them), but now mean
        ; "load from a file" rather than "load from DATA" - see the *READ/
        ; *SAVE siblings in the second extension table (EXT2, below) for the
        ; rest of the family this table no longer has room for.
        ext_keyword_rts "CHRLOAD",  BASIC_CHRLOAD
        ext_keyword_rts "PALLOAD",  BASIC_PALLOAD
        ext_keyword_rts "OAMLOAD",  BASIC_OAMLOAD
        ext_keyword_rts "SPRITE",   BASIC_SPRITE
        ext_keyword_rts "SPRTILE",  BASIC_SPRTILE
        ext_keyword_rts "SPRX",     BASIC_SPRX
        ext_keyword_rts "SPRY",     BASIC_SPRY
        ext_keyword_rts "SPRCOLOR", BASIC_SPRCOLOR
        ext_keyword_rts "SPRFLIP",  BASIC_SPRFLIP
        ext_keyword_rts "SPRPRI",   BASIC_SPRPRI
        ; File I/O (see docs/basic-file.md): OPEN/CLOSE/BGET#/BPUT# against
        ; MIA's SD/FAT layer. "OPEN"/"CLOSE" chosen over the primary table to
        ; keep that table's tight 256-byte budget untouched.
        ext_keyword_rts "OPEN",    BASIC_OPEN
        ext_keyword_rts "CLOSE",   BASIC_CLOSE
        ext_keyword_rts "BGET#",   BASIC_BGET
        ext_keyword_rts "BPUT#",   BASIC_BPUT
        end_ext_token_tables

; ----------------------------------------------------------------------------
; Second extension keyword table (two-byte tokens: TOKEN_EXT2 + subtoken).
; The first extension table (above) filled up its 256-byte keyword-name
; budget once the video/audio asset family and MIALOAD/MIASAVE landed - same
; problem TOKEN_EXTFN already solved once for the function table. See
; docs/basic-file.md.
; ----------------------------------------------------------------------------
        init_ext2_token_tables
        ; Video/audio asset family: *READ bulk-loads from DATA exactly as
        ; CHRLOAD/PALLOAD/OAMLOAD/BGLOAD used to (BGLOAD itself is retired -
        ; its interleaved nametable+attribute case is now NTREAD/NTLOAD +
        ; ATRREAD/ATRLOAD). CHRLOAD/PALLOAD/OAMLOAD (still in the first
        ; table, above) now mean "from an SD file" instead, matching LOAD's
        ; real meaning; *SAVE is the reverse.
        ext2_keyword_rts "NTREAD",   BASIC_NTREAD
        ext2_keyword_rts "NTLOAD",   BASIC_NTLOAD
        ext2_keyword_rts "NTSAVE",   BASIC_NTSAVE
        ext2_keyword_rts "ATRREAD",  BASIC_ATRREAD
        ext2_keyword_rts "ATRLOAD",  BASIC_ATRLOAD
        ext2_keyword_rts "ATRSAVE",  BASIC_ATRSAVE
        ext2_keyword_rts "CHRREAD",  BASIC_CHRREAD
        ext2_keyword_rts "CHRSAVE",  BASIC_CHRSAVE
        ext2_keyword_rts "PALREAD",  BASIC_PALREAD
        ext2_keyword_rts "PALSAVE",  BASIC_PALSAVE
        ext2_keyword_rts "OAMREAD",  BASIC_OAMREAD
        ext2_keyword_rts "OAMSAVE",  BASIC_OAMSAVE
        ; Generic MIA RAM loader/saver (see docs/basic-file.md).
        ext2_keyword_rts "MIALOAD",  BASIC_MIALOAD
        ext2_keyword_rts "MIASAVE",  BASIC_MIASAVE
        ; Filesystem management (see docs/basic-file.md). RMDIR shares
        ; KILL's body: FatFs's f_unlink already deletes either a file or an
        ; empty directory.
        ext2_keyword_rts "SEEK#",    BASIC_SEEK
        ext2_keyword_rts "KILL",     BASIC_KILL
        ext2_keyword_rts "RMDIR",    BASIC_KILL
        ext2_keyword_rts "MKDIR",    BASIC_MKDIR
        ext2_keyword_rts "NAME",     BASIC_NAME
        ; Directory navigation/listing (see docs/basic-file.md). CD relies on
        ; FatFs's own current-directory tracking (FF_FS_RPATH) - every other
        ; path-taking command above resolves a relative path against it for
        ; free, no changes needed to any of them.
        ext2_keyword_rts "CD",       BASIC_CD
        ext2_keyword_rts "DIR",      BASIC_DIR
        end_ext2_token_tables

; ----------------------------------------------------------------------------
; Extension FUNCTION keyword table (two-byte tokens: TOKEN_EXTFN + subtoken).
; The primary function table (UNFNC above) has no room left (256-byte budget,
; ~1 byte free before this), so background-PLAY's status function lives here
; instead - it costs nothing in the primary table. TOKENIZE_EXTFN runs before
; TOKENIZE_EXT (program.s) so "PLAYING" is not truncated to the "PLAY"
; statement + leftover "ING".
; ----------------------------------------------------------------------------
        init_extfn_token_tables
        extfn_keyword_addr "PLAYING", BASIC_PLAYING
        ; EOF(n) - see docs/basic-file.md.
        extfn_keyword_addr "EOF",     BASIC_EOF
        end_extfn_token_tables
.endif
