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
;;;                     main loop) or destroys W, preserves W

        list p=16F18855
	include p16f18855.inc
        CONFIG RSTOSC=HFINT1, FEXTOSC=OFF, ZCD=ON, WDTE=OFF, LVP=OFF

;;; Constants
OLED_I2C_ADDRESS:	equ 0x78


;;; --------------------- Utility macros ---------------------
MOVLWF  macro field, value
	movlw value
	movwf field
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
	movlw eot-bot
	call put_string_in_code
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
	MOVLWF  OSCCON1, 0X62
	clrf    OSCCON3
	clrf    OSCEN
	MOVLWF  OSCFRQ, 0x02
	clrf    OSCTUNE

;;; SSP1 specific init (see also pins)
	movlb 0x03
	MOVLWF SSP1ADD, 0x09	; 100khz at 4Hz clock
	MOVLWF SSP1CON1, 0x28	; SPEN, mode master I2C to SSP1CON1

;;; eusart_init:
	banksel PIE3
	bcf     PIE3, 0x5
	bcf     PIE3, 0x4

;;; USART
	banksel BAUD1CON
	MOVLWF  BAUD1CON, 0x08
;;; BDOVF no_overflow; SCKP Non-Inverted;
;;; BRG16 16bit_generator; WUE disabled; ABDEN disabled

	MOVLWF  RCSTA, 0x90
	;; SPEN enabled; RX9 8-bit; CREN enabled; ADDEN disabled; SREN
	;;  disabled;

	MOVLWF  TXSTA, 0x24
;; TX9 8-bit; TX9D 0; SENDB sync_break_complete; TXEN enabled;
;; SYNC asynchronous; BRGH hi_speed; CSRC slave;
	MOVLWF  SPBRGL, 0x19 ; 9600 Bd@4Mhz
	clrf    SPBRGH

;;; --------------------------------------------
;;; Stack init
	MOVLWF FSR0L, 0x20
	clrf FSR0H

;;;
	UART_PRINT "\r\nv1\r\n"

;;; -------------------- Main loop ----------------
main_loop:
	;; Show prompt, read char.
	;; if char is number,
	movlw '>'
	call t_write_char
	call do_receive
	addlw   -0x3a
	IFNCARRY goto    small_thing
	addlw   0x3a
	movlb   0
	movwf   LATA
	call    t_write_char
	movwf   INDF0
	call    print_octet

main_ok:
	UART_PRINT "Ok\r\n>"
	goto main_loop

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
	goto fill_r0_low			;4
	goto main_loop			;5
	goto main_loop			;6
	goto main_loop			;7
	goto main_loop			;8
	goto main_loop			;9

;;; ---------------- Utilities ------------------
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
	call tos_to_fsr1
put_string_b:
	moviw FSR1++
	call t_write_char
	decfsz INDF0, F
	goto put_string_b
	movlw 0x0a
	call t_write_char
	movlw 0x0d
	call t_write_char
fsr1_to_tos:			; any -- unspecified
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
	movlw 0x80		; no continuation, next is command
	call t_send_i2c_octet
	moviw --FSR0
	call t_send_i2c_octet
	goto t_send_i2c_stop

OLED_CMD macro value
	movlw value
	call t_send_oled_cmd
	endm

fill_r0_low:
	movlw 0
	call oled_set_row
	movlw 0x04
	movwf INDF0
	movlw 80
send_oled_data_fill:
	;; send W copies of indf
	movwi ++FSR0
	call send_i2c_address
	movlw 0x40		; continuation, next is data
	call t_send_i2c_octet
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
	movlw 0x40		; continuation, next is data
	call t_send_i2c_octet
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
	movlw high(oled_init_code)
	movwf FSR1H
	movlw low(oled_init_code)
	movwf FSR1L
	movlw oled_init_code_end - oled_init_code
	movwf INDF0
	call send_i2c_address
oled_more_cmds:
	movlw 0x80		; no continuation, next is command
	call t_send_i2c_octet
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

oled_put_picture2:
	OLED_CMD 0xB2		; row 0
	OLED_CMD 0x10		; col 0
	OLED_CMD 0x00		; col 0
	MOVLWF FSR1H, high(font)
	MOVLWF FSR1L, low(font)
	movlw 64
	goto send_oled_data_fsr1

oled_put_picture1:
	OLED_CMD 0xB0		; row 0
	OLED_CMD 0x10		; col 0
	OLED_CMD 0x00		; col 0
	MOVLWF FSR1H, high(font)
	MOVLWF FSR1L, low(font)
	movlw 64
	goto send_oled_data_fsr1

font:
    ;; this is from an example code for the board
    dt 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x5F,0x00,0x00,0x00,0x07,0x00,0x07,0x00 ;	'sp,!,"
    dt 0x14,0x7F,0x14,0x7F,0x14 ; #
    dt 0x24,0x2A,0x7F,0x2A,0x12,0x23,0x13,0x08,0x64,0x62,0x36,0x49,0x56,0x20,0x50 ;	'$,%,&
    dt 0x00,0x08,0x07,0x03,0x00,0x00,0x1C,0x22,0x41,0x00,0x00,0x41,0x22,0x1C,0x00 ;	'',(,)
    dt 0x2A,0x1C,0x7F,0x1C,0x2A,0x08,0x08,0x3E,0x08,0x08,0x00,0x00,0x70,0x30,0x00 ;	'*,+,,
    dt 0x08,0x08,0x08,0x08,0x08,0x00,0x00,0x60,0x60,0x00,0x20,0x10,0x08,0x04,0x02 ;	'-,.,/
    dt 0x3E,0x51,0x49,0x45,0x3E,0x00,0x42,0x7F,0x40,0x00,0x72,0x49,0x49,0x49,0x46 ;	'0,1,2
    dt 0x21,0x41,0x49,0x4D,0x33,0x18,0x14,0x12,0x7F,0x10,0x27,0x45,0x45,0x45,0x39 ;	'3,4,5
    dt 0x3C,0x4A,0x49,0x49,0x31,0x41,0x21,0x11,0x09,0x07,0x36,0x49,0x49,0x49,0x36 ;	'6,7,8
    dt 0x46,0x49,0x49,0x29,0x1E,0x00,0x00,0x14,0x00,0x00,0x00,0x40,0x34,0x00,0x00 ;	'9,:,;
    dt 0x00,0x08,0x14,0x22,0x41,0x14,0x14,0x14,0x14,0x14,0x00,0x41,0x22,0x14,0x08 ;	'<,=,>
    dt 0x02,0x01,0x59,0x09,0x06,0x3E,0x41,0x5D,0x59,0x4E                          ;       '?,@
    dt 0x7C,0x12,0x11,0x12,0x7C                                                   ;	'A
    dt 0x7F,0x49,0x49,0x49,0x36,0x3E,0x41,0x41,0x41,0x22,0x7F,0x41,0x41,0x41,0x3E ;	'B,C,D
    dt 0x7F,0x49,0x49,0x49,0x41,0x7F,0x09,0x09,0x09,0x01,0x3E,0x41,0x41,0x51,0x73 ;	'E,F,G
    dt 0x7F,0x08,0x08,0x08,0x7F,0x00,0x41,0x7F,0x41,0x00,0x20,0x40,0x41,0x3F,0x01 ;	'H,I,J
    dt 0x7F,0x08,0x14,0x22,0x41,0x7F,0x40,0x40,0x40,0x40,0x7F,0x02,0x1C,0x02,0x7F ;	'K,L,M
    dt 0x7F,0x04,0x08,0x10,0x7F,0x3E,0x41,0x41,0x41,0x3E,0x7F,0x09,0x09,0x09,0x06 ;	'N,O,P
    dt 0x3E,0x41,0x51,0x21,0x5E,0x7F,0x09,0x19,0x29,0x46,0x26,0x49,0x49,0x49,0x32 ;	'Q,R,S
    dt 0x03,0x01,0x7F,0x01,0x03,0x3F,0x40,0x40,0x40,0x3F,0x1F,0x20,0x40,0x20,0x1F ;	'T,U,V
    dt 0x3F,0x40,0x38,0x40,0x3F,0x63,0x14,0x08,0x14,0x63,0x03,0x04,0x78,0x04,0x03 ;	'W,X,Y
    dt 0x61,0x59,0x49,0x4D,0x43                                                   ;  'Z
    dt 0x00,0x7F,0x41,0x41,0x41,0x02,0x04,0x08,0x10,0x20                          ;	'[,\
    dt 0x00,0x41,0x41,0x41,0x7F,0x04,0x02,0x01,0x02,0x04,0x40,0x40,0x40,0x40,0x40 ;	'],^,_
    dt 0x00,0x03,0x07,0x08,0x00,0x20,0x54,0x54,0x38,0x40,0x7F,0x28,0x44,0x44,0x38 ;	'`,a,b
    dt 0x38,0x44,0x44,0x44,0x28,0x38,0x44,0x44,0x28,0x7F,0x38,0x54,0x54,0x54,0x18 ;	'c,d,e
    dt 0x00,0x08,0x7E,0x09,0x02,0x0C,0x52,0x52,0x4A,0x3C,0x7F,0x08,0x04,0x04,0x78 ;	'f,g,h
    dt 0x00,0x44,0x7D,0x40,0x00,0x20,0x40,0x40,0x3D,0x00,0x7F,0x10,0x28,0x44,0x00 ;	'i,j,k
    dt 0x00,0x41,0x7F,0x40,0x00,0x7C,0x04,0x78,0x04,0x78,0x7C,0x08,0x04,0x04,0x78 ;	'l,m,n
    dt 0x38,0x44,0x44,0x44,0x38,0x7C,0x18,0x24,0x24,0x18,0x18,0x24,0x24,0x18,0x7C ;	'o,p,q
    dt 0x7C,0x08,0x04,0x04,0x08,0x48,0x54,0x54,0x54,0x24,0x04,0x04,0x3F,0x44,0x24 ;	'r,s,t
    dt 0x3C,0x40,0x40,0x20,0x7C,0x1C,0x20,0x40,0x20,0x1C,0x3C,0x40,0x30,0x40,0x3C ;	'u,v,w
    dt 0x44,0x28,0x10,0x28,0x44,0x4C,0x50,0x50,0x50,0x3C,0x44,0x64,0x54,0x4C,0x44 ;	'x,y,z
    dt 0x00,0x08,0x36,0x41,0x00,0x00,0x00,0x77,0x00,0x00,0x00,0x41,0x36,0x08,0x00 ;	'{,|,}
    dt 0x02,0x01,0x02,0x04,0x02

 end
