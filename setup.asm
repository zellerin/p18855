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
