;;; -*- mode: pic-asm; -*-
;;;
;;; Playing with Microchip Express Board using i2c.
;;; Features:
;;; - usart using default board features
;;; - dispatch-driven using the usart impit
;;; - I2C to OLED using standard CPU places (it means that labels SDA
;;;   and SCL on the board are swapped - however, it enables to plug
;;;   my oled directly to the board)
;;; - interrupts not used; there is nothing to do waiting for
;;;   peripherals, and make code simple.
;;;
;;; Code conventions:
;;; - INDF0 is a scratch register
;;; - function pass arguments in frs0[-1] and so on
;;; - The fact that direct addresses are used is a misfeature to fix eventually
;;;
        list p=16F18855
	org 0
	include p16f18855.inc

MOVLWF  macro field, value
	movlw value
	movwf field
	endm

IFZERO  macro cmd
	btfsc   0x03, 2
	cmd
	endm

IFCARRY macro cmd
	btfsc 0x03, 0
	cmd
	endm

IFNCARRY macro cmd
	btfss 0x03, 0
	cmd
	endm

MOVLBS	macro bank
	BANKSEL bank*128
	endm

PUSH_VALUE macro value
	movlw value
	movwi FSR0++
	endm

POP	macro
	moviw --4
	endm

OLED_I2C_ADDRESS:	equ 0x78
main:
;;; clean_pmd:
	banksel PMD0
	clrf    PMD0
	clrf    PMD1
	clrf    PMD2
	clrf    PMD3
	clrf    PMD4
	clrf    PMD5

;;; pin_init:
	banksel 0
	clrf    0x16
	clrf    0x17
	MOVLWF  0x18, 0x41 ; C6 high (RX on Click), C0 high (TX - USB)
	MOVLWF  0x11, 0xf0	; A0 to A3 output (LED), A4-A7 in (POT, SW1, Alarms)
	MOVLWF  0X12, 0XFF
	MOVLWF  0x13, 0xfe	; C0 (TX-USB) input, i2c pins input

	movlb   0x1e  ; ----------- BANK 30, 0xf.. -----------------
	MOVLWF  0x4e, 0xe5 ; anselc - digital input for RX-USB, RC3, RC4
	MOVLWF  0x43, 0xff  ; anselb - no digital input
	movwf   ANSELA ; no digital input
	movwf   WPUB
	MOVWF   WPUA
	MOVWF   WPUC
	MOVLWF  0x65, 0x08
	clrf    ODCONA
	clrf    ODCONB
	clrf    ODCONC
	movwf   SLRCONA
	movwf   SLRCONB
	movwf   SLRCONC
	MOVLWF  RC0PPS, 0x10	; TX/CK
	MOVLWF  RC4PPS, 0X15	; SDA1
	MOVLWF  RC3PPS, 0x14	; SCL1

	movlb   0x1d
	MOVLWF  RXPPS, 0x11	; RC1
	MOVLWF  SSP1DATPPS, 0x14	; RC4
	MOVLWF  SSP1CLKPPS, 0x13	; RC3

;;; osc_init:
	banksel OSCCON1
	MOVLWF  OSCCON1, 0X62 ; osccon1
	clrf    OSCCON3	; osccon3
	clrf    OSCEN	; oscen
	MOVLWF  OSCFRQ, 0x02 ; oscfrq
	clrf    0x12	; osctune

;;; SSP1 specific init (see also pins)
	movlb 0x03
	MOVLWF 0x0d, 0x09	; SSP1ADD - 100khz at 4Hz clock
	MOVLWF 0x10, 0x28		; SPEN, mode master I2C to SSP1CON1

;;; eusart_init:
	banksel PIE3
	bcf     PIE3, 0x5	; pie3 - rcie
	bcf     PIE3, 0x4	; pie3 - 0719

;;; USART
	banksel BAUD1CON
	MOVLWF  BAUD1CON, 0x08    ; baud1con
;;; BDOVF no_overflow; SCKP Non-Inverted;
;;; BRG16 16bit_generator; WUE disabled; ABDEN disabled

	MOVLWF  0x1d, 0x90	; rcsta
	;; SPEN enabled; RX9 8-bit; CREN enabled; ADDEN disabled; SREN
	;;  disabled;


	MOVLWF  0x1e, 0x24	; txsta
;; TX9 8-bit; TX9D 0; SENDB sync_break_complete; TXEN enabled;
;; SYNC asynchronous; BRGH hi_speed; CSRC slave;
	MOVLWF  SPBRGL, 0x19 ; spbrgl
	clrf    SPBRGH	; spbrgh

;;; --------------------------------------------
;;; Stack init
	MOVLWF 0x04, 0x20
	clrf 0x05

;;;
	call    put_string_in_code
	DT "Ready:", 0

main_loop
	call    do_receive
	addlw   -0x3a
	IFNCARRY goto    small_thing
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
	IFNCARRY goto main_ok
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
	banksel PIR3
	movf  PIR3, W		; PIR3
	movwf 0
	call print_octet
	movlb 3
	movf  0x10, W 		; SSP1CON1
	movwf 0
	call print_octet
	movlb 3
	movf  SSP1CON2, W
	movwf 0
	call print_octet
	movlb 3
	movf  SSP1STAT, W
	movwf 0
	call print_octet

clear_pir3:
	banksel PIR3
	bcf  PIR3,1
	return

do_receive:
	banksel PIR3
	btfss PIR3, RCIF
	goto do_receive
	movlb 0x02
	movf RCREG, W
	return

put_string_b:
;;; Write string pointed from FSR1 till zero octet
	moviw  1++
	IFZERO return
	call    write_char
	goto    put_string_b

tos_to_fsr1:
	banksel TOSH
	decf STKPTR, F 		; on top is call to us...
	movf TOSH, W
	addlw 0x80
	movwf FSR1H
	movf TOSL, W
	movwf FSR1L
	incf STKPTR, F
	return

put_string_in_code:
;;; Write string pointed from FSR1 till zero octet and newline
;;; get FSR1 from TOS
	call tos_to_fsr1
	call    put_string_b
	movlw   0x0a
	call write_char
	movlw   0x0d
	call write_char
fsr1_to_tos:
	banksel TOSL
	;; high bit set seems not to be a problem
	movf FSR1H, W
	movwf TOSH
	movf FSR1L, W
	movwf TOSL
	return

write_char:
;;; write char at W. Keeps W unchanged.
	banksel PIR3
	btfss   PIR3, TXIF
	goto    write_char
	banksel TX1REG
	movwf  TX1REG
	return


ALLOC	macro
	incf 0x04, F ; FSR0
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
	IFCARRY addlw   0x7
	addlw   0x3a
	goto write_char

wait_clean_sspif:
	;; wait for SSPIF. Make sure we leave at bank 3.
	banksel PIR3
	btfss PIR3, 0 		; ssp1IF
	goto wait_clean_sspif
	bcf PIR3, 0
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
	call wait_clean_sspif
	movlb 0x03
	btfss 0x11, 6 		; ACKSTAT
	return
	goto got_noack

got_noack:
	call put_string_in_code
	dt "noack", 0
	return

send_i2c_stop:
	movlb 0x03
	bsf   0x11 ,2 		; PEN
	goto wait_clean_sspif

send_oled_cmd:
	PUSH_VALUE 0x80		; no continuation, next is command
send_oled_cmd_or_data:
	PUSH_VALUE OLED_I2C_ADDRESS
	call send_i2c_address
	call send_i2c_octet
	call send_i2c_octet
	goto send_i2c_stop

send_oled_cmds:
	;; send commands from IFR1 till zero byte
	call tos_to_fsr1
	PUSH_VALUE 0x78
	call send_i2c_address
	call oled_more_cmds
	goto fsr1_to_tos

oled_more_cmds:
	moviw 1
	IFZERO goto send_i2c_stop
	PUSH_VALUE 0x80		; no continuation, next is command
	call send_i2c_octet
	moviw 1++
	movwi 0++
	call send_i2c_octet
	goto oled_more_cmds

send_oled_data_fsr1:
	;; send W commands from IFR1
	movwf 0x7f
	PUSH_VALUE 0x78
	call send_i2c_address
	PUSH_VALUE 0x40		; continuation, next is data
	call send_i2c_octet
oled_more_data:
	moviw 1++
	movwi 0++
	call send_i2c_octet
	decfsz 0x7f
	goto oled_more_data
	goto send_i2c_stop

send_oled_data:
	PUSH_VALUE 0xc0		; no continuation, next is command
	goto send_oled_cmd_or_data

OLED_CMD macro value
	PUSH_VALUE value
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
	call send_oled_cmds
	data 0x8d, 0x14, 0xaf, 0x00 ; charge and on
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
	MOVLWF FSR1H, high(random_image)
	MOVLWF FSR1L, low(random_image)
	movlw 12
	goto send_oled_data_fsr1

random_image:
	dt 0x3c, 0x3c, 0xc3, 0xc3, 0x3c, 0x3c
	dt 0x3c, 0x3c, 0xc3, 0xc3, 0x3c, 0x3c

	CONFIG RSTOSC=HFINT1, FEXTOSC=OFF, ZCD=ON, WDTE=OFF, LVP=OFF
	end
