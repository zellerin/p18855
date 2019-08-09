	org 0

main:
;;; clean_pmd:
	movlb   0x0f
	clrf    0x16
	clrf    0x17
	clrf    0x18
	clrf    0x19
	clrf    0x1a
	clrf    0x1b

;;; pin_init:
	movlb   0x00
	clrf    0x16
	clrf    0x17
	movlw   0x41
	movwf   0x18	; C6 high (RX on Click), C0 high (TX - USB)
	movlw   0xf0	; A0 to A3 output (LED), A4-A7 in (POT, SW1, Alarms)
	movwf   0x11
	movlw   0xff
	movwf   0x12
	movlw   0xfe
	movwf   0x13	; C0 (TX-USB) input, i2c pins input
	movlb   0x1e  ; ----------- BANK 30, 0xf.. -----------------
	movlw   0xe5
	movwf   0x4e	; anselc - digital input for RX-USB, RC3, RC4
	movlw   0xff
	movwf   0x43	; anselb - no digital input
	movwf   0x38	; ansela - no digital input
	movwf   0x44	; wpub
	movwf   0x39	; wpua
	movwf   0x4f	; wpuc
	movlw   0x08
	movwf   0x65	; wpue
	clrf    0x3a	; odcona
	clrf    0x45	; odconb
	clrf    0x50	; odconc
	movwf   0x3b	; slrcona
	movwf   0x46	; slrconb
	movwf   0x51	; slrconc
	movlw   0x10	; RC0
	movwf   0x20	; rc0pps
	movlw   0x15	; SDA1
	movwf   0x24	; rc4pps
	movlw   0x14	; SCL1
	movwf   0x23	; rc3pps

	movlb   0x1d	; ------------ BANK 29, 0xE8. ----------------
	movlw   0x11	; RC1
	movwf   0x4b	; RXPPS, def RC7
	movlw   0x14
	movwf   0x46	; SSP1DATPPS
	movlw   0x13
	movwf   0x45	; SSP1CLKPPS

;;; osc_init:
	movlb   0x11
	movlw   0x62
	movwf   0x0d 	; osccon1
	clrf    0x0f	; osccon3
	clrf    0x11	; oscen
	movlw   0x02
	movwf   0x13	; oscfrq
	clrf    0x12	; osctune

;;; SSP1 specific init (see also pins)
	movlb 0x03
	movlw 0x09		; 100khz at 4Hz clock
	movwf  0x0D		; SSP1ADD
	movlw 0x28		; SPEN, mode master I2C
	movwf 0x10		; SSP1CON1

;;; eusart_init:
	movlb   0x0e
	bcf     0x19, 0x5	; pie3 - rcie
	movlb   0x0e
	bcf     0x19, 0x4	; pie3 - 0719
;;; USART
	movlw   0x08
	movlb   0x02
;;; BDOVF no_overflow; SCKP Non-Inverted;
;;; BRG16 16bit_generator; WUE disabled; ABDEN disabled
	movwf   0x1f 	; baud1con

	movlw   0x90
	;; SPEN enabled; RX9 8-bit; CREN enabled; ADDEN disabled; SREN
	;;  disabled;
	movwf   0x1d	; rcsta

	movlw   0x24
;; TX9 8-bit; TX9D 0; SENDB sync_break_complete; TXEN enabled;
;; SYNC asynchronous; BRGH hi_speed; CSRC slave;
	movwf   0x1e	; txsta
	movlw   0x19
	movwf   0x1b	; spbrgl
	clrf    0x1c	; spbrgh
;;; --------------------------------------------
;;; Stack init
	movlw 0x20
	movwf 0x04
	clrf 0x05


;;;
	movlw   low(receive_and_display)
	movwf   0x06
	movlw   high(receive_and_display)
	movwf   0x07
	call    puts
main_loop
	call    do_receive
	addlw   -0x3a
	btfss   3, 0 		; status/carry
	goto    small_thing
	addlw   0x3a
	movlb   0
	movwf   0x16			; LATA - show bits
	call    write_char
	movwf   0
	call    print_octet

;	call    oled_on
main_ok:
	movlw   0x0d
	call    write_char
	movlw   0x0a
	call    write_char
	movlw   0x4f
	call    write_char
	movlw   0x6b
	call    write_char
	movlw   0x3e
	call    write_char
	goto    main_loop

small_thing:
	addlw 0x0a
	btfss 3,0
	goto main_ok
	call dispatcher
	goto main_loop

dispatcher:
	brw
	goto oled_off				;0
	goto oled_on				;1
	goto oled_put_picture1			;2
	goto oled_put_picture2 			;3
	goto send_i2c_address			;4
	goto send_i2c_address			;5
	goto send_i2c_address			;6
	goto send_i2c_address			;7
	goto send_i2c_address			;8
	goto send_i2c_address			;9

show_pir:
	movlb 0x0e
	movf  0x0f, W		; PIR3
	movwf 0
	call print_octet
	movlb 3
	movf  0x10, W 		; SSP1CON1
	movwf 0
	call print_octet
	movlb 3
	movf  0x11, W 		; SSP1CON2
	movwf 0
	call print_octet
	movlb 3
	movf  0xf, W 		; SSP1STAT
	movwf 0
	call print_octet

clear_pir3:
	movlb 0x0e
	bcf  0x0f,1
	return

do_receive:
	movlb 0x0e
	btfss 0x0f, 0x5	; PIR3.RCIF
	goto do_receive
	movlb 0x02
	movf 0x19, W
	return

put_string_b:
;;; Write string pointed from FSR1 till zero octet
	moviw   1++
	btfsc   0x03, 0x2
	return
	call    write_char
	goto    put_string_b

puts:
;;; Write string pointed from FSR1 till zero octet and newline
	call    put_string_b
	movlw   0x0a
	;; fall through

write_char:
;;; write char at W. Keeps W unchanged.
	movlb   0x0e
	btfss   0x0f, 0x4	; PIR3.TXIF
	goto    write_char
	movlb   0x02
	movwf   0x1a		; TX1REG
	return


ALLOC	macro
	incf 0x04, F ; FSR0
	endm

POP	macro
	moviw --4
	endm

print_octet:
	swapf 0, W
	call print_nibble
	movf 0, W
	call print_nibble
	movlw 0x20
	goto write_char

print_nibble:
	;; Convert nibble to ascii and put to the screen
	andlw   0x0f
	addlw   0xf6
	btfsc   0x03, 0 ; STATUS, C
	addlw   0x7
	addlw   0x3a
	goto write_char

wait_clean_sspif:
	;; wait for SSPIF. Make sure we leave at bank 3.
	movlb 0x0e
	btfss 0x0f, 0 		; ssp1IF
	goto wait_clean_sspif
	bcf 0x0f, 0
	return

;;; I2C
send_i2c_address:
	;; address in INDF0
	movlb 0x03
	bsf   0x11, 0		; SEN
	call wait_clean_sspif
send_i2c_octet:
	movlb 0x03
	moviw --4		; INDF
	movwf 0x0c		; SSP1BUF
	call print_octet
	call wait_clean_sspif
	movlb 0x03
	btfss 0x11, 6 		; ACKSTAT
	goto got_ack
	goto got_noack

got_ack:
	return
	;; if needed debug:
	movlw   low(ack)
	movwf   0x06
	movlw   high(ack)
	movwf   0x07
	goto    puts

got_noack:
	movlw   low(noack)
	movwf   0x06
	movlw   high(noack)
	movwf   0x07
	goto    puts

send_i2c_stop:
	movlb 0x03
	bsf   0x11 ,2 		; PEN
	goto wait_clean_sspif

send_oled_cmd:
	movlw 0x78
	movwi 4++
	call send_i2c_address
	movlw 0x80		; no continuation, next is command
	movwi 4++
	call send_i2c_octet
	call send_i2c_octet
	goto send_i2c_stop

send_oled_cmds:
	;; send commands fro IFR1 till zero byte
	movlw 0x78
	movwi 4++
	call send_i2c_address
oled_more_cmds:
	moviw 1
	btfsc 3, 2		; zero?
	goto send_i2c_stop
	movlw 0x80		; no continuation, next is command
	movwi 4++
	call send_i2c_octet
	moviw 1++
	movwi 0++
	call send_i2c_octet
	goto oled_more_cmds

send_oled_data:
	movlw 0x78
	movwi 4++
	call send_i2c_address
	movlw 0xc0		; no continuation, next is command
	movwi 4++
	call send_i2c_octet
	call send_i2c_octet
	goto send_i2c_stop

OLED_CMD macro value
	movlw value
	movwi 4++
	call send_oled_cmd
	endm

OLED_DATA macro value
	movlw value
	movwi 4++
	call send_oled_data
	endm

oled_off:
        OLED_CMD 0xAE  ;  Set OLED Display Off
	return

oled_on:
	movlw high(oled_on_cmds)
	movwf 7
	movlw low(oled_on_cmds)
	movwf 6
	goto send_oled_cmds

oled_on_cmds:
	retlw 0x8d
	retlw 0x14
        retlw 0xAF  ;  Set OLED Display On
	retlw 0
	return

oled_put_picture2:
	OLED_CMD 0xB0		; row 0
	OLED_CMD 0x10		; col 0
	OLED_CMD 0x00		; col 0
	movlw 39
	movwf 0
fill_in_55:
	incf 4
	OLED_DATA 0x55
	decf 4
	decfsz 0, F
	goto fill_in_55
	return

oled_put_picture1:
	OLED_CMD 0xB0		; row 0
	OLED_CMD 0x10		; col 0
	OLED_CMD 0x00		; col 0
	movlw 39
	movwf 0
fill_in_aa:
	incf 4
	OLED_DATA 0xAA
	decf 4
	decfsz 0, F
	goto fill_in_aa
	return

	OLED_CMD 0xAE
	OLED_CMD 0xD5
	OLED_CMD 0x80
	OLED_CMD 0xa8
	OLED_CMD 0x39
	OLED_CMD 0xa1
	OLED_CMD 0xc8
        OLED_CMD 0x40  ; Set Display Start Line
        OLED_CMD 0xD3  ; Set Display Offset
        OLED_CMD 0xDA  ; Set COM Pins Hardware Configuration
        OLED_CMD 0x81  ;  Set Contrast Control
        OLED_CMD 0xD9  ;  Set Pre-Charge Period
        OLED_CMD 0xDB  ;  Set VCOMH Deselect Level
        OLED_CMD 0xA4  ;  Set Entire Display On/Off
        OLED_CMD 0xA6  ;  Set Normal/Inverse Display
        OLED_CMD 0xAF  ;  Set OLED Display On
	return

;;; Data
receive_and_display:
	retlw   0x31
	retlw   0x65
	retlw   0x63
	retlw   0x65
	retlw   0x69
	retlw   0x76
	retlw   0x65
	retlw   0x20
	retlw   0x61
	retlw   0x6e
	retlw   0x64
	retlw   0x20
	retlw   0x44
	retlw   0x69
	retlw   0x73
	retlw   0x70
	retlw   0x6c
	retlw   0x61
	retlw   0x79
	retlw   0x00


noack:
	retlw 'N'
	retlw 'O'
ack:
	retlw 'A'
	retlw 'C'
	retlw 'K'
	retlw 0x00

	CONFIG RSTOSC=HFINT1, FEXTOSC=OFF, ZCD=ON, WDTE=OFF, LVP=OFF
	end
