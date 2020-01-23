;;; -*- mode: pic-asm; -*-
;;;
;;; Playing with Microchip Express Board using i2c.
;;; Features:
;;; - usart using default board features
;;; - dispatch-driven using the usart impit
;;; - I2C to OLED (GM009605) using standard CPU places (it means that labels SDA
;;;   and SCL on the board are swapped - however, it enables to plug
;;;   my oled directly to the board)
;;; - interrupts not used; there is nothing to do waiting for the
;;;   peripherals, and make code simple.
;;;
;;; Code conventions:
;;; - INDF0 is a scratch register
;;; - function pass octet arguments in W, INDF0, addresses in FSR1
;;;
;;; Problems & next actions
;;; - The fact that direct addresses are used is a misfeature to fix eventually
;;; - Parameter passing unification:
;;;
;;; Function name prefixes:
;;; - t_ :: tiny, does not change W nor INDF0
;;; - d_ :: dirty, modifies INDF
;;; - without prefix :: either not callable (part of init, part of
;;;                     main loop) or destroys W, preserves INDF

	include p16f18855.inc
        CONFIG RSTOSC=HFINT1, FEXTOSC=OFF, ZCD=ON, WDTE=OFF, LVP=OFF

;;; Constants
OLED_I2C_ADDRESS:	equ 0x78


;;; --------------------- Utility macros ---------------------
CALL1	macro target, parameter
	movlw parameter
	call target
	endm

MOVLWF  macro field, value
	movlw value
	movwf field
	endm

MOVLWD macro hi, lo, value
	MOVLWF hi, high(value)
	MOVLWF lo, low(value)
	endm

IFCARRY macro cmd
	btfsc STATUS, C
	cmd
	endm

IFNCARRY macro cmd
	btfss STATUS, C
	cmd
	endm

UART_PRINT macro text
	local bot
	local eot
	CALL1 put_string_in_code, eot-bot
bot:	dt text
eot:
	endm

	org 0
	include "setup.asm"

position:	EQU 0x20
;;; Stack init

	MOVLWF FSR0L, 0x22
	clrf FSR0H

;;; Initialization done
	UART_PRINT "\r\nv1\r\n"

;;; -------------------- Main loop ----------------
main_loop:
	;; Show prompt, read char.  if char is a digit, dispatch to
	;; appropriate subroutine in dispatecher. If not, show bit of char on
	;; LEDs (PORTA), write char back, show it on screen and go on
	CALL1 t_write_char,  '>'
	call do_receive
	addlw   -('9'+1)	; may be digit
	IFNCARRY goto maybe_digit
	addlw   '9'+1		; add back to original value
	banksel LATA
	movwf   LATA
main_print:
	call    t_write_char
	call    oled_send_char

main_ok:
	;; Report success and start anew
	UART_PRINT "Ok\r\n>"
	goto main_loop

not_a_digit:
	addlw '0'
	goto main_print

maybe_digit:
	;; Receives char-'9'-1; adds back 9+1 to find out if it is a digit.
	addlw 0x0a
	IFNCARRY goto not_a_digit; not a digit
	call dispatcher		;
	goto main_loop

dispatcher:
	;; Bug: some return (goto main_loop), some not (oled_on)
	brw
	goto oled_off				;0
	goto oled_on				;1
	goto oled_put_picture1			;2
	goto oled_put_picture2 			;3
	goto fill_r0_low			;4
	goto print_position			;5
	goto main_loop			;6
	goto main_loop			;7
	goto main_loop			;8
	goto main_loop			;9

print_position:
	CALL1 print_octet_w, position
	banksel position
	movf position, W
	goto print_octet_w

;;; ---------------- UART input ------------------
do_receive:
	banksel PIR3
	btfss PIR3, RCIF
	goto do_receive
	movlb 0x02
	movf RCREG, W
	return

nibble_to_hexa:
	andlw   0x0f
	addlw   0xf6
	IFCARRY addlw   0x7
	addlw   0x3a
	return

;;; ---------------- UART output -----------------

print_nibble:
	;; Convert nibble to hexadecimal digit and send to usart
	;; | reg | in     | out        |
	;; |-----+--------+------------|
	;; | W   | nibble | hexa digit |
	call nibble_to_hexa

t_write_char:
	banksel PIR3
	btfss   PIR3, TXIF
	goto    t_write_char
	banksel TX1REG
	movwf  TX1REG
	return

print_octet_w:
	movwf INDF0
print_octet:
	;; Print octet followed by space.
	;; | reg   | in             | out          |
	;; |-------+----------------+--------------|
	;; | INDF0 | octet to print | unchanged    |
	;; | W     | unused         | returns 0x20 |
	swapf INDF0, W
	call print_nibble
	movf INDF0, W
	call print_nibble
	movlw 0x20
	goto t_write_char

put_string_in_code:
	;; Write W chars in code pointed from TOS,followed by CLRF
	;; | reg   | in               | out         |
	;; |-------+------------------+-------------|
	;; | W     | length of text   | undefined   |
	;; | TOS   | address to print | returned to |
	;; | INDF0 | destroyed        | 0           |
	;; | FSR1  | destroyed        | undefined   |
	movwi INDF0
	banksel TOSH
	movf TOSH, W
	addlw 0x80
	movwf FSR1H
	movf TOSL, W
	movwf FSR1L
put_string_b:
	moviw FSR1++
	call t_write_char
	decfsz INDF0, F
	goto put_string_b
	CALL1 t_write_char, 0x0a
	CALL1 t_write_char, 0x0d
fsr1_to_tos:			; any -- TOSL
	banksel TOSL
	;; high bit set seems not to be a problem
	movf FSR1H, W
	movwf TOSH
	movf FSR1L, W
	movwf TOSL
	return

;;; ----------------- I²C ----------------------

t_wait_clean_sspif: 		; no pars
	banksel PIR3
	btfss PIR3, 0 		; ssp1IF
	goto t_wait_clean_sspif
	bcf PIR3, 0
	return

send_i2c_address:		;
	movlb 0x03
	bsf   0x11, 0		; SEN
	call t_wait_clean_sspif
	movlw OLED_I2C_ADDRESS
	;; fall through
t_send_i2c_octet:
	movlb 0x03
	movwf SSP1BUF		; SSP1BUF
	call t_wait_clean_sspif
	movlb 0x03
	btfss SSP1CON2, ACKSTAT
	return

got_noack:			; error situation
	UART_PRINT "noack"
	return

t_send_i2c_stop:
	movlb 0x03
	bsf SSP1CON2, PEN
	goto t_wait_clean_sspif

t_send_oled_cmd:
	movwi ++FSR0
	call send_i2c_address
	CALL1 t_send_i2c_octet, 0x80 ;; no continuation, next is command
	moviw FSR0--
	call t_send_i2c_octet
	goto t_send_i2c_stop

OLED_CMD macro value
	CALL1 t_send_oled_cmd, value
	endm

fill_r0_low:
	call oled_put_picture2
	MOVLWF INDF0, 0x04
	movlw 80
send_oled_data_fill:
	;; send W copies of indf
	movwi ++FSR0
	call send_i2c_address
	CALL1 t_send_i2c_octet, 0x40; continuation, next is data
oled_fill_more_data:
	moviw -1[0]
	call t_send_i2c_octet
	decfsz INDF0
	goto oled_fill_more_data
	movwi FSR0--
	goto t_send_i2c_stop

send_oled_data_fsr1:
	;; send W data from IFR1
	movwf INDF0
	call send_i2c_address
	CALL1 t_send_i2c_octet, 0x40 ; ; continuation, next is data
oled_more_data:
	moviw 1++
	call t_send_i2c_octet
	decfsz INDF0
	goto oled_more_data
	goto t_send_i2c_stop

oled_off:
        OLED_CMD 0xAE  ;  Set OLED Display Off
	return

oled_on:
	;; see Figure 2 of SSD1306 docs
	MOVLWD FSR1H, FSR1L, oled_init_code
	MOVLWF INDF0, oled_init_code_end - oled_init_code
	call send_i2c_address
oled_more_cmds:
	CALL1 t_send_i2c_octet, 0x80		; no continuation, next is command
	moviw 1++
	call t_send_i2c_octet
	decfsz INDF0
	goto oled_more_cmds
	goto t_send_i2c_stop

oled_init_code:
	dt "\xA8\x3f\xd3\x00\x40\xa0\xc0\x81\x7f\xa4\xa6\x0d\x80\x8d\x14\xaf"
oled_init_code_end:

oled_set_row_col:
	;; Set column and row based on rownum
	;; row is rownum mod 8 (reverted)
	banksel 0
	movf position, W
	andlw 0x07
	xorlw 0xb7 		; also invert!
	call t_send_oled_cmd
	;; col is 12xrownum mod 8 = 12x(rownum and 0xF8)/8 = 3*(rownum and 0xf8)/2
	banksel position
	movf position, W
	andlw 0xf8
	movwf INDF0		; rownum & 0xf8
	lsrf INDF0, F		; (rownum & oxf8)/2
	addwf INDF0, F		; column
	swapf INDF0, W
	andlw 0x0f
	iorlw 0x10
	call t_send_oled_cmd
	movf INDF0, W
	andlw 0x0f
	call t_send_oled_cmd
	return

oled_send_char:
	;; W contains char
	addlw -0x20
	;; W is now 0x00 to 0x5e
	;; we know that fonts start at low addr0
	movwf FSR1L
	movlw high(font)
	movwf FSR1H
	lslf FSR1L,W		; x2
	addwf FSR1L,F		; x3 in F
	movlw 4
	btfsc STATUS, C
	addwf FSR1H, F
	call oled_set_row_col 	; W can be modified now ;)
	banksel position
	incf position, F
	lslf FSR1L,F		; x6 - carry possible now, means +2
	movlw 2
	btfsc STATUS, C
	addwf FSR1H, F
	lslf FSR1L,F		; x12 - carry possible now
	btfsc STATUS, C
	incf FSR1H
	movlw 0x0c 		; octets per char in font
	goto send_oled_data_fsr1

oled_put_picture2:
	banksel position
	clrf position
	goto oled_set_row_col

oled_put_picture1:
	banksel position
	clrf position
	call oled_set_row_col
	MOVLWD FSR1H, FSR1L, font
	movlw 0xFF
	goto send_oled_data_fsr1

	include "font8x12.asm"

 end
