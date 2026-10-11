.segment "CODE"
; ----------------------------------------------------------------------------
; ISCNTC - Clementina: ask the kernel's break check (KERN_STOP) whether
; Ctrl-C was typed, like CBM BASIC calling the KERNAL's STOP. Falls through
; into STOP on a break, with A=$03, Z=1 and C=1 as the other targets do; other
; keys stay queued in the kernel for GET and INPUT.
; ----------------------------------------------------------------------------
ISCNTC:
        jsr KERN_STOP
        beq @stopit
        rts
@stopit:
;!!! runs into "STOP"
