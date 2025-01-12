; VIA registers
PORTB = $6000
PORTA = $6001
DDRB  = $6002
DDRA  = $6003
T1CL  = $6004    ; Timer 1 Low Order Counter
T1CH  = $6005    ; Timer 1 High Order Counter
T1LL  = $6006    ; Timer 1 Low Order Latch
T1LH  = $6007    ; Timer 1 High Order Latch
ACR   = $600b    ; Auxiliary Control Register
PCR   = $600c    ; Peripheral Control Register
IFR   = $600d    ; Interrupt Flag Register
IER   = $600e    ; Interrupt Enable Register

; LCD control bits
E  = %10000000
RW = %01000000
RS = %00100000

; Variables
time_h = $00
time_m = $01
time_s = $02
temp   = $05      ; For BCD conversion
timer_count = $06 ; Count timer interrupts

  .org $8000

reset:
  sei              ; Disable interrupts
  ldx #$ff
  txs              ; Initialize stack pointer
  
  ; Set up VIA
  lda #%11111111   ; PORTB = output
  sta DDRB
  lda #%11100000   ; PORTA = LCD control output
  sta DDRA
  
  ; Set up Timer1 for continuous interrupts
  ; For testing, let's use a shorter interval: 10,000 cycles (0x2710)
  lda #%01000000   ; T1 continuous interrupts
  sta ACR          ; Set VIA Auxiliary Control Register first
  lda #$10         ; Low byte of timer value
  sta T1LL         ; Store in latch
  lda #$27         ; High byte of timer value
  sta T1LH         ; Store in latch
  sta T1CH         ; Writing to T1CH starts the timer

  ; Set up CB1 interrupt
  lda #%00000000   ; Set CB1 to interrupt on falling edge
  sta PCR
  
  ; Enable both Timer1 and CB1 interrupts
  lda #%11010000   ; Enable Timer1 (bit 6) and CB1 (bit 4)
  sta IER

  ; Set up LCD
  jsr lcd_wait
  lda #%00111000   ; 8-bit mode, 2-line
  jsr lcd_instruction
  lda #%00001100   ; Display on, cursor off
  jsr lcd_instruction
  lda #%00000110   ; Increment address
  jsr lcd_instruction
  lda #%00000001   ; Clear display
  jsr lcd_instruction

  ; Initialize time to 12:00:00
  lda #12
  sta time_h
  lda #0
  sta time_m
  sta time_s
  sta timer_count
  
  cli              ; Enable interrupts

main_loop:
  jsr display_time
  jmp main_loop

display_time:
  lda #%10000000  ; First line
  jsr lcd_instruction
  
  ; Display hours
  lda time_h
  jsr convert_bcd
  ora #"0"
  jsr lcd_char
  lda temp
  ora #"0"
  jsr lcd_char
  
  ; Display :
  lda #":"
  jsr lcd_char
  
  ; Display minutes
  lda time_m
  jsr convert_bcd
  ora #"0"
  jsr lcd_char
  lda temp
  ora #"0"
  jsr lcd_char

  ; Display :
  lda #":"
  jsr lcd_char
  
  ; Display seconds
  lda time_s
  jsr convert_bcd
  ora #"0"
  jsr lcd_char
  lda temp
  ora #"0"
  jsr lcd_char
  rts

; Convert number in A to BCD
; Returns: A = tens, temp = ones
convert_bcd:
  ldx #0
div10:
  cmp #10
  bcc div10_done
  sec
  sbc #10
  inx
  jmp div10
div10_done:
  sta temp
  txa
  rts

; LCD functions
lcd_wait:
  pha
  lda #%00000000  ; PORTB = input
  sta DDRB
lcd_busy:
  lda #RW
  sta PORTA
  lda #(RW | E)
  sta PORTA
  lda PORTB
  and #%10000000
  bne lcd_busy

  lda #RW
  sta PORTA
  lda #%11111111  ; PORTB = output
  sta DDRB
  pla
  rts

lcd_instruction:
  jsr lcd_wait
  sta PORTB
  lda #0          ; Clear RS/RW/E
  sta PORTA
  lda #E          ; Set E
  sta PORTA
  lda #0          ; Clear E
  sta PORTA
  rts

lcd_char:
  jsr lcd_wait
  sta PORTB
  lda #RS         ; Set RS
  sta PORTA
  lda #(RS | E)   ; Set E
  sta PORTA
  lda #RS         ; Clear E
  sta PORTA
  rts

; Interrupt handler
irq:
  pha             ; Save A
  txa
  pha             ; Save X
  
  ; Check if it's Timer1 interrupt
  lda IFR
  and #%01000000  ; Check Timer1 bit
  beq check_cb1   ; If not Timer1, check CB1
  
  ; Clear Timer1 interrupt flag
  sta IFR

  ; Increment our test counter and debug
  inc timer_count
  lda timer_count
  cmp #100        ; After 100 timer interrupts
  bne irq_done
  lda #0
  sta timer_count
  
  ; Update seconds
  inc time_s
  lda time_s
  cmp #60
  bne irq_done
  
  ; Second rolled over
  lda #0
  sta time_s
  
  ; Update minutes
  inc time_m
  lda time_m
  cmp #60
  bne irq_done
  
  ; Minute rolled over
  lda #0
  sta time_m
  
  ; Update hours
  inc time_h
  lda time_h
  cmp #13
  bne irq_done
  lda #1
  sta time_h
  
  jmp irq_done

check_cb1:
  ; Check for CB1 interrupt (SELECT button)
  lda IFR
  and #%00010000  ; Check CB1 bit (bit 4)
  beq irq_done
  
  ; Clear CB1 interrupt flag
  sta IFR
  
  ; Increment minutes on SELECT press
  inc time_m
  lda time_m
  cmp #60
  bne irq_done
  lda #0
  sta time_m
  inc time_h
  lda time_h
  cmp #13
  bne irq_done
  lda #1
  sta time_h

irq_done:
  pla             ; Restore X
  tax
  pla             ; Restore A
  rti

  .org $fffc
  .word reset
  .word irq       ; Point to our interrupt handler
