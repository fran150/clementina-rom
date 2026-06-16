.segment "CODE"
ISCNTC:
        jsr MONRDKEY_NB
        bcc @NOTHING
        cmp #$03
        beq @STOPIT
@NOTHING:
        rts
@STOPIT:
;!!! runs into "STOP"
