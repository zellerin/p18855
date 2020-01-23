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
;;; ------- Initialization --------------
;;; clean_pmd:
	banksel PMD0
	clrf    PMD0
	clrf    PMD1
	clrf    PMD2
	clrf    PMD3
	clrf    PMD4
	clrf    PMD5

;;; Pin assingment:
;;; - UART over USB is on RC0 (TX) and RC1 (RX)
;;; - OLED display is over RC3 (SDA) and RC4 (SCL)
;;; - Internal LEDs on board are fed by A0 to A3;
;;;
	banksel 0
	clrf    LATA
	clrf    LATB
	MOVLWF  LATC, b'01000001' ; high are C6 (RX on Click) and C0 (TX - USB)
	MOVLWF  TRISA, b'11110000'; A0 to A3 output (LED), A4-A7 input (POT, SW1, Alarms)
	MOVLWF  TRISB, -1
	MOVLWF  TRISC, ~b'1'	; C0 (TX-USB) input, i2c pins input

	banksel 0xf00  ; ----------- BANK 30, 0xf.. -----------------
	MOVLWF  ANSELC, 0xe5 ; digital input for RX-USB, RC3, RC4
	; MOVLWF  ANSELB, -1  ; default - no digital input
	; movwf   ANSELA ; default; no digital input
	; MOVLWF  WPUB, -1   ; enable all pulups
	; MOVWF   WPUA
	; MOVWF   WPUC
	MOVLWF  WPUE, 0x08
	; clrf    ODCONA 		; default
	; clrf    ODCONB		; default
	; clrf    ODCONC		; default
	; movwf   SLRCONA		; slew rate, default -1, BUG here
	; movwf   SLRCONB
	; movwf   SLRCONC
	MOVLWF  RC0PPS, 0x10	; TX/CK
	MOVLWF  RC4PPS, 0x15	; SDA1
	MOVLWF  RC3PPS, 0x14	; SCL1

	banksel 0xe80
	MOVLWF  RXPPS, 0x11	        ; RC1
	MOVLWF  SSP1DATPPS, 0x14	; RC4
	MOVLWF  SSP1CLKPPS, 0x13	; RC3

;;; osc_init: What follows are defaults for CONFIG RSTOSC=HFINT1
	; banksel OSCCON1
	; MOVLWF  OSCCON1,0x62 	; HFINTOSC, divider 4
	; clrf    OSCCON3
	; clrf    OSCEN
	; MOVLWF  OSCFRQ, 0x02	; 4Mhz
	; clrf    OSCTUNE ; minimum frequency - BUG

;;; SSP1 specific init (see also pins)
	banksel SSP1ADD
	MOVLWF SSP1ADD, 0x09	; 100khz at 4MHz clock

	;; | name  | bit     | val |
	;; |-------+---------+-----|
	;; | SSPM  | 0-3     |   8 |
	;; | CKP   | H'0004' |   0 |
	;; | SSPEN | H'0005' |   1 |
	;; | SSPOV | H'0006' |   0 |
	;; | WCOL  | H'0007' |   0 |
	MOVLWF SSP1CON1, 0x28

;;; Interrupts setup - no interrupts atm, default
	; banksel PIE3
	;; | name   | bit     | val |
	;; |--------+---------+-----|
	;; | SSP1IE | H'0000' |   0 |
	;; | BCL1IE | H'0001' |   0 |
	;; | SSP2IE | H'0002' |   0 |
	;; | BCL2IE | H'0003' |   0 |
	;; | TXIE   | H'0004' |   0 |
	;; | RCIE   | H'0005' |   0 |
	; MOVLWF PIE3, 0x0f

;;; USART
	banksel BAUD1CON
	bsf  BAUD1CON, BRG16
	;; | name   | bit     | val | comment             |
	;; |--------+---------+-----+---------------------|
	;; | ABDEN  | H'0000' |   0 | no autobaud         |
	;; | WUE    | H'0001' |   0 | wake up disabled    |
	;; | N/A    | 2       |   0 |                     |
	;; | BRG16  | H'0003' |   1 | 16bit timer for baud |
	;; | SCKP   | H'0004' |   0 | idle TX is high      |
	;; | n/a    | 5       |   X |
	;; | RCIDL  | H'0006' |   X | RO                  |
	;; | ABDOVF | H'0007' |   X | RO                  |
	;; default 0

	MOVLWF  RCSTA, 0x90
	;; default 0
	;; | name  | bit     | value |                   |
	;; |-------+---------+-------+-------------------|
	;; | RX9D  | H'0000' |     X |                   |
	;; | OERR  | H'0001' |     X |                   |
	;; | FERR  | H'0002' |     X |                   |
	;; | ADDEN | H'0003' |     0 | no address detect |
	;; | CREN  | H'0004' |     1 | continuous receive |
	;; | SREN  | H'0005' |     X | unused in async mode
	;; | RX9   | H'0006' |     0 | 8bit reception        |
	;; | SPEN  | H'0007' |     1 | serial enabled    |

	MOVLWF  TXSTA, 0x24
	;; | TX9D       | H'0000' | 0 |
	;; | TRMT       | H'0001' | 0 |
	;; | BRGH       | H'0002' | 1 | high speed
	;; | SENDB      | H'0003' | 0 |
	;; | SYNC       | H'0004' | 0 | asynchronous
	;; | TXEN       | H'0005' | 1 | enable
	;; | TX9        | H'0006' | 0 | 8 bit transmission
	;; | CSRC       | H'0007' | 0 | slave

	MOVLWF  SPBRGL, 0x19 ; SPBGR=0x19, 4000khz/16*(25+1)=9.615
	clrf    SPBRGH

;;; Stack init
	MOVLWF FSR0L, 0x20
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
	call    t_write_char
	call    oled_send_char

main_ok:
	;; Report success and start anew
	UART_PRINT "Ok\r\n>"
	goto main_loop

maybe_digit:
	;; Receives char-'9'-1; adds back 9+1 to find out if it is a digit.
	addlw 0x0a
	IFNCARRY goto main_ok	; not a digit, ignore
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
	goto main_loop			;5
	goto main_loop			;6
	goto main_loop			;7
	goto main_loop			;8
	goto main_loop			;9

;;; ---------------- Utilities ------------------
tos_to_fsr1:

;;; ---------------- UART input ------------------
do_receive:
	banksel PIR3
	btfss PIR3, RCIF
	goto do_receive
	movlb 0x02
	movf RCREG, W
	return

;;; ---------------- UART output -----------------

t_write_char:
	banksel PIR3
	btfss   PIR3, TXIF
	goto    t_write_char
	banksel TX1REG
	movwf  TX1REG
	return

print_nibble:	      ; nibble -- char
	;; Convert nibble to ascii and put to the screen
	andlw   0x0f
	addlw   0xf6
	IFCARRY addlw   0x7
	addlw   0x3a
	goto t_write_char

print_octet:			; octet any -- octet 0x20
	swapf INDF0, W
	call print_nibble
	movf INDF0, W
	call print_nibble
	movlw 0x20
	goto t_write_char

put_string_in_code:		; any length -- 0 unspecified
;;; Write string pointed from FSR1 till zero octet and newline
;;; get FSR1 from TOS
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
	movwi FSR0++
	call send_i2c_address
	CALL1 t_send_i2c_octet, 0x80 ;; no continuation, next is command
	moviw --FSR0
	call t_send_i2c_octet
	goto t_send_i2c_stop

OLED_CMD macro value
	CALL1 t_send_oled_cmd, value
	endm

fill_r0_low:
	CALL1 oled_set_row, 0
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

oled_set_row:
	andlw 0x07
	addlw 0xb0
	call t_send_oled_cmd
	OLED_CMD 0x10		; col 0
	OLED_CMD 0x00		; col 0
	return

oled_send_char:
	;; W contains char
	addlw -0x20
	;; W is now 0x00 to 0x5e
	;; we know that FSR0 is 0
	movwf FSR1L
	movlw high(font)
	movwf FSR1H
	lslf FSR1L,W		; x2
	addwf FSR1L,F		; x3 in W
	lslf FSR1L,F		; x6 - carry possible now
	movlw 2
	btfsc STATUS, C
	addwf FSR1H, F
	lslf FSR1L,F		; x6 - carry possible now
	btfsc STATUS, C
	incf FSR1H
	movlw 0x0c 		; octets per char in font
	goto send_oled_data_fsr1

oled_put_picture2:
	OLED_CMD 0xB0		; row 0
	OLED_CMD 0x10		; col 0
	OLED_CMD 0x00		; col 0
	return

oled_put_picture1:
	OLED_CMD 0xB0		; row 0
	OLED_CMD 0x10		; col 0
	OLED_CMD 0x00		; col 0
	MOVLWD FSR1H, FSR1L, font
	movlw 64
	goto send_oled_data_fsr1

	include "font8x12.asm"

 end
