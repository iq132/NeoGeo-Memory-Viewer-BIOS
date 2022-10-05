*-------------------------------------------------------------------------------------------------------------
* Title      : NeoGeo Memory Viewer BIOS 
* Written by : iq_132
* Date       : October 5, 2022
* Description: A drop-in replacement for the NeoGeo BIOS that allows the user to view and write to any address
*              in the NeoGeo's memory space. This bios *WILL NOT BOOT GAMES* and is not designed to.               
*-------------------------------------------------------------------------------------------------------------

; standard NeoGeo memory locations
RAMSTART            equ     $100000             ; 68K's work RAM
BIOS_SYSTEM_MODE    equ     $10fd80             ; 1 byte - 80 set if use vblank handler in cart, not set if otherwise
REG_P1CNT           equ     $300000             ; read p1 controller
REG_DIPSW           equ     $300001             ; read dipswitch, write/reset watchdog
REG_STATUS_B        equ     $380000             ; read coin, start buttons
REG_SWPBIOS         equ     $3a0003             ; swap in the bios' vectors (to $0)
REG_BRDFIX          equ     $3a000b             ; swap in the bios' fix & z80 roms
REG_PALBANK0        equ     $3a001f             ; use palette bank 0
REG_VRAMADDR        equ     $3c0000             ; set position in graphics/fix ram
REG_VRAMRW          equ     $3c0002             ; write to/read from graphics/fix ram
REG_VRAMMOD         equ     $3c0004             ; set value to increment position in graphics/fix ram after writes
REG_IRQACK          equ     $3c000c             ; acknowledge interrupts
PALETTES            equ     $400000             ; Palette RAM
SYSROM              equ     $c00000             ; bios' location in the 68k's memory map

START_BUFFER        equ     $10fd00             ; 1 byte - hold previous 'start' input
SELECT_FUNCTION     equ     $10fd01             ; 1 byte - which function? (poke, poke address, poke value, or viewer address)
DRAW_FLAGS          equ     $10fd02             ; 1 byte - set bits to enable drawing

    ; the 68k bios is mapped at c00000, the vectors (0-ff) of the bios can be swapped into address 0 of the 68k's memory space
    ; when this happens, the cartridge's vectors are mapped at c00000-c000ff
    ORG     SYSROM
START:                                          ; first instruction of program

    ; set up 'vector' table
    dc.l    RAMSTART+$f300                      ; $00 - default SP
    dc.l    _init                               ; $04 - entry point
    dc.l    _init                               ; $08 - entry point
    dc.l    _init                               ; $0c - entry point
    dc.l    _init                               ; $10 - entry point

    ; interrupts start at 1 ($64)
    ORG     SYSROM+$64                          ; irqs
    dc.l    _vblank                             ; $64
    dc.l    _raster_irq                         ; $68

    ; the NeoGeo bios has a jump table at $402 with calls to a variety of functions-replace some of these.
    ORG    SYSROM+$402

    jmp     _init                               ; these should all point to the same routine (based on actual bios)
    jmp     _init
    jmp     _init
    jmp     _init
    jmp     _init
    jmp     _init
    jmp     _init
    jmp     _init
    jmp     _init

    ; jump for vblank is located here
    ORG     SYSROM+$438

    jmp     _vblank                             ; point to vblank routine

    ; start actual functionality here
    ORG    SYSROM+$800


; initialize the hardware
_init
    move.w  #$2700, SR                          ; disable interrupts
    lea     RAMSTART+$f300, A7                  ; set sp
	move.b	D0, REG_DIPSW	                    ; reset watchdog
	move.w  #$7, REG_IRQACK                     ; clear acks - 100% required during hardware init!
    
    move.b  D0, REG_SWPBIOS                     ; use bios vector
    move.b  D0, REG_BRDFIX                      ; use bios sfix rom
    move.b  D0, REG_PALBANK0                    ; use palette bank 0
    
    clr.b   BIOS_SYSTEM_MODE                    ; ensure we don't get vblank from cart
    
	lea.l	RAMSTART, A0	                    ; view start
	lea.l	RAMSTART, A2	                    ; poke start
	lea.l   $0, A3                              ; poke value

    ; clear main ram
    lea.l   RAMSTART, A4                        ; main ram
    move.w  #$3c7f, D1                          ; (f300/4)-1
_clearramloop
        clr.l  (A4)+
        dbra    D1, _clearramloop

	move.b	D0, REG_DIPSW	                    ; reset watchdog

    ; clear palette ram
    lea.l   PALETTES, A4                        ; palette ram
    move.w  #$7ff, D1                           ; (2000/4)-1
_paletteclear_loop
        clr.l  (A4)+
        dbra    D1, _paletteclear_loop

    ; basic colors
    move.w  #$8000,  PALETTES+$0                ; black - must be 8000!
    move.w  #$999,   PALETTES+$2                ; gray
    move.w  #$4fc0,  PALETTES+$22               ; gray (2)
    move.w  #$7fff,  PALETTES+$42               ; white

	move.b	D0, REG_DIPSW	                    ; reset watchdog

    ; clear fix layer
    move.w  #$4ff, D0                           ; fix layer is 40*32 in size (40*32)-1
    move.w  #$7000, REG_VRAMADDR                ; offset 7000 (e000/2) in graphics ram
    move.w  #$1, REG_VRAMMOD                    ; advance 1 entry
_blank_loop
            move.w  #$20, REG_VRAMRW            ; $20 is ' ' tile
        dbra    D0, _blank_loop

    ; draw initial viewer screen
    move.b  #$1f, DRAW_FLAGS                    ; force redraw everything!

    bsr   _redraw

    moveq.l #$0, D7                             ; clear inputs
	move.w  #$2000, SR                          ; enable interrupts

    ; sit in a busy loop and wait for the vblank to trigger
_init_loop
    bra.s   _init_loop


;   dummy function for raster (irq 2) calls (just in case)
_raster_irq
	move.w  #$7, REG_IRQACK                     ; ack irq
    move.w  #$2000, SR                          ; enable interrupts
	rte


; this function is called at the beginning of the vblank period
; logic and drawing are performed here
_vblank
	move.w  #$7, REG_IRQACK                     ; ack irq
	move.b	D0, REG_DIPSW                       ; reset watchdog

    movem.l D0-D6/A4-A6, -(A7)

	; input handling
	move.b	D7, D6                              ; copy previous inputs to D6
	move.b	REG_P1CNT, D7                       ; copy current p1 inputs to D7
	not.b	D7                                  ; invert inputs
    
    clr.b  DRAW_FLAGS                           ; disable all draw flags

    ; input check loop
	moveq.l	#$7, D5
_input_loop
        ; check for button pressed -> button not pressed transition
		btst	D5, D6                                          ; was the button previously pressed or not?
		beq 	_skip_this_one                                  ; it wasn't - skip
			btst	D5, D7                                      ; is the button currently pressed?
			bne 	_skip_this_one                              ; it isn't - skip

			    lsl.w   #$2, D5                                 ; this selects which value we're adding

			    cmp.b   #$0, SELECT_FUNCTION                    ; function 0 - add to the viewer address - only ffff00 is changed
			    bne.s   _poke_set_address_high
                    lea.l   _vw_add_lut, A1
			    	adda.l  (A1,D5.w), A0
			    	ori.b   #$1, DRAW_FLAGS                     ; force redraw of viewer address
                    bra   _vblank_end
_poke_set_address_high
			        cmp.b   #$1, SELECT_FUNCTION                ; function 1 - add to poke address (ffff00) high bits
			        bne.s   _poke_set_address_low
                        lea.l   _vw_add_lut, A1
			    	    adda.l  (A1,D5.w), A2
			    	    ori.b   #$2, DRAW_FLAGS                 ; force redraw of poke address high bits
                        bra    _vblank_end
_poke_set_address_low
			            cmp.b   #$2, SELECT_FUNCTION            ; function 2 - add to poke address (ff) low bit - note bit 0 must always be 0!
			            bne.s   _poke_set_value
                            lea.l   _vw_add_lut_lo, A1
			    	        adda.l  (A1,D5.w), A2
			    	        ori.b   #$6, DRAW_FLAGS             ; force redraw of poke address high and low bits
                            bra     _vblank_end
_poke_set_value
			                    cmp.b   #$3, SELECT_FUNCTION    ; function  3 - add to poke value
			                    bne.s   _poke_poke
                                    lea.l   _pk_add_lut_lo, A1
			    	                adda.l  (A1,D5.w), A3
			    	                ori.b   #$8, DRAW_FLAGS     ; force redraw of poke value
                                    bra.s   _vblank_end
_poke_poke
                                    move.w  A3, (A2)            ; function 4 - poke address with value
                                    bra.s   _vblank_end         ; redraw only viewer
_skip_this_one
	dbra	D5, _input_loop

    ; check for 'start' button presses
    move.b  REG_STATUS_B, D5                    ; start 1, start 2, etc
    not.b   D5                                  ; invert
    andi.b  #$1, D5                             ; isolate
    tst.b   D5                                  ; is start button pressed?
    bne.s   _start_pressed                      ; yes? skip
        tst.b   START_BUFFER                    ; previously start button pressed?
        beq.s   _start_pressed                  ; no? skip
            addq.b  #$1, SELECT_FUNCTION        ; functions 0-4
            cmpi.b  #$4, SELECT_FUNCTION
            ble.s   _less_than_equal_or         ; > 4, loop back to 0
                clr.b  SELECT_FUNCTION
_less_than_equal_or
            move.b  D5, START_BUFFER
            move.b  #$1f, DRAW_FLAGS            ; force redraw of everything
            bra.s   _vblank_end
_start_pressed
    move.b  D5, START_BUFFER                    ; buffer start button

_vblank_end
    movem.l (A7)+, D0-D6/A4-A6
    ; force update only on change or watch for active changes?
    ; let's just constantly update
    bsr.s   _redraw
    move.w  #$2000, SR                          ; enable interrupts
    rte


; function to draw characters onto the screen
_redraw
	move.b	D0, REG_DIPSW	                    ; reset watchdog

    ; draw 'viewer' address
    btst.b  #$0, DRAW_FLAGS
    beq.s   _skip_redraw_viewer_address
	    moveq.l	#$0, D3		                    ; match byte
	    move.w	#$7086, REG_VRAMADDR	        ; place in fix ram
	    moveq.l	#$5, D1		                    ; how many characters to draw
	    move.l	A0, D0		                    ; set initial value
	    rol.l   #$4, D0                         ; adjust initial value
	    rol.l   #$8, D0                         ; adjust initial value
	    bsr 	_draw_view_poke_data  
_skip_redraw_viewer_address

	; write the data to the screen
	move.w	#$20, REG_VRAMMOD                   ; +1 for horizontal position on screen for every write to fix ram
    move.l  A0, A1                              ; make backup of A0 so that we can modify it
	move.w	#$7088, D3                          ; on-screen (fix ram) starting position
    move.w  #$2000, D2                          ; color

    ; draw data to viewer
	moveq.l	#$f, D0                             ; 16 bytes high
_outer_loop
		move.w	D3, REG_VRAMADDR                ; set this row's starting position to fix ram

		moveq.l	#$f, D1                         ; 16 bytes wide (actually draws 32 characters)
_inner_loop
			move.b	(A1), D2                    ; read byte - note that top byte is color! only use byte accesses!
			lsr.b	#$4, D2                     ; isolate top nibble
			cmp.b   #$9, D2                     ; <= 9
			ble.s   _not_10_1                   ; yes, skip
		        addq.b   #$7, D2                ; no += 7
_not_10_1
			add.b	#$30, D2                    ; add 30 (ascii)
			move.w	D2, REG_VRAMRW              ; move to fix ram

			move.b	(A1)+, D2                   ; read byte
			andi.b	#$f, D2                     ; isolate lowest nibble
			cmpi.b  #$9, D2                     ; <= 9
			ble.s   _not_10_2                   ; yes, skip
		        addq.b   #$7, D2                ; no += 7
_not_10_2
			addi.b	#$30, D2                    ; add 30 (ascii)
			move.w	D2, REG_VRAMRW              ; move to fix ram

		dbra D1, _inner_loop

		addq.b	#$1, D3                         ; +1 to vertical position on-screen

	dbra	D0, _outer_loop
 
;   draw the poke address (high)!
    btst.b  #$1, DRAW_FLAGS
    beq.s   _skip_redraw_poke_address
	    moveq.l	#$1, D3		                    ; match byte
	    move.w	#$7099, REG_VRAMADDR	        ; place in fix ram
	    moveq.l	#$3, D1		                    ; how many characters to draw
	    move.l	A2, D0		                    ; set initial value
	    rol.l   #$4, D0                         ; adjust initial value
	    rol.l   #$8, D0                         ; adjust initial value
	    bsr 	_draw_view_poke_data 
_skip_redraw_poke_address

;   draw the poke address (low)!
    btst.b  #$2, DRAW_FLAGS
    beq.s   _skip_redraw_poke_address_low
	    moveq.l	#$2, D3		                    ; match byte
	    move.w	#$7119, REG_VRAMADDR	        ; place in fix ram
	    moveq.l	#$1, D1		                    ; how many characters to draw
	    move.l	A2, D0		                    ; set initial value
	    ror.l   #$4, D0                         ; adjust initial value
	    bsr 	_draw_view_poke_data

    move.w  #$3a, REG_VRAMRW                    ; ":" text
_skip_redraw_poke_address_low

;   draw the poke value!
    btst.b  #$3, DRAW_FLAGS
    beq.s   _skip_redraw_poke_value
	    moveq.l	#$3, D3		                    ; match byte
	    move.w	#$7179, REG_VRAMADDR	        ; place in fix ram
	    moveq.l	#$3, D1		                    ; how many characters to draw
	    move.l	A3, D0		                    ; set initial value
	    swap	D0                              ; adjust initial value
	    rol.l	#$4, D0		                    ; adjust initial value
	    bsr.s	_draw_view_poke_data 
_skip_redraw_poke_value

;   draw '[POKE]'
    btst.b  #$4, DRAW_FLAGS
    beq.s   _skip_redraw_poke_poke
        move.w #$20, $3c0004
        move.w  #$71f9, REG_VRAMADDR            ; place in fix ram - 7000 + (15x * 32cols) + 25y
        moveq.l  #$0, D2                        ; set to inactive color
        cmp.b   #$4, SELECT_FUNCTION            ; match byte
        bne.s   _skip_poke_color                ; change color if we've selected this
            move.w  #$1000, D2                  ; set to 'active' color
_skip_poke_color
        ; draw "[POKE]" on screen
        move.b  #$5b, D2                        ; '['
        move.w  D2, REG_VRAMRW
        move.b  #$50, D2                        ; 'P'
        move.w  D2, REG_VRAMRW
        move.b  #$4f, D2                        ; 'O'
        move.w  D2, REG_VRAMRW
        move.b  #$4b, D2                        ; 'K'
        move.w  D2, REG_VRAMRW
        move.b  #$45, D2                        ; 'E'
        move.w  D2, REG_VRAMRW
        move.b  #$5d, D2                        ; ']'
        move.w  D2, REG_VRAMRW
_skip_redraw_poke_poke

    clr.b    DRAW_FLAGS                         ; set all drawn
    rts

; common function to print a hex string on screen
_draw_view_poke_data
	move.w	#$20, REG_VRAMMOD                   ; advance by +1 column after every write in fix ram
    moveq.l  #$0, D2                            ; clear color (set inactive color)
	cmp.b   SELECT_FUNCTION, D3                 ; compare the currently active function against this one
	bne.s   _not_address                        ; no match? skip
	    move.w  #$1000, D2                      ; match? set color as active
_not_address
_current_address_loop
		move.b  D0, D2                          ; move lowest bits into bottom of color data
		andi.b  #$f, D2                         ; isolate lowest nibble
		cmpi.b  #$9, D2                         ; value <= 9
		ble.s   _not_10                         ; yes? skip
			addq.b   #$7, D2	                ; value > 9? value += 7
_not_10
		addi.b  #$30, D2                        ; value += 30 (ascii)
		rol.l   #$4, D0                         ; value = (value >> 28) | (value << 4);
		move.w  D2, REG_VRAMRW                  ; write to fix ram
	dbra    D1, _current_address_loop
	rts

; add/subtract tables for button presses
; - viewer address table - note lowest byte of address is not touched as we always want it to be 00
; - also used for poke address high bits
_vw_add_lut    dc.l    $ffffff00, $00000100, $fffff000, $00001000, $ffff0000, $00010000, $fff00000, $00100000   ; -100, +100, -1000, +1000, -10000, +10000, -100000, +100000
; - poke address table - low bits - note that this does not touch bit 0, writing a word to an odd address on 68k hardware is BAD.
_vw_add_lut_lo dc.l    $fffffffe, $00000002, $fffffff0, $00000010, $0, $0, $0, $0   ; -2, +2, -10, +10, -0, +0, -0, +0
; - poke value table
_pk_add_lut_lo dc.l    $ffffffff, $00000001, $fffffff0, $00000010, $ffffff00, $00000100, $fffff000, $00001000   ; -1, +1, -10, +10, -100, +100, -1000, +1000

    ; set c1ffff to ff, this is optional, but causes the assembled binary to be 128k in size
    ORG    SYSROM+$1fffe
    dc.w    $ffff

    END    START                                ; last line of source
