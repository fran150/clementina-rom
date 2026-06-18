.segment "CODE"
; ----------------------------------------------------------------------------
; ISCNTC - Clementina: check the input FIFO for Ctrl-C (break).
; Falls through into STOP when Ctrl-C is seen, like the other targets.
; ----------------------------------------------------------------------------
ISCNTC:
        jsr MONRDKEY_NB
        bcc @nothing
        cmp #$03
        beq @stopit
@nothing:
        rts
@stopit:
;!!! runs into "STOP"
