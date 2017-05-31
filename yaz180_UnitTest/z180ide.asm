;==============================================================================
; Contents of this file are copyright Phillip Stevens
;
; You have permission to use this for NON COMMERCIAL USE ONLY
; If you wish to use it elsewhere, please include an acknowledgement to myself.
;
; https://github.com/feilipu/
;
; https://feilipu.me/
;
;
; http://wiki.osdev.org/ATA_PIO_Mode

;==============================================================================
;
; INCLUDES SECTION
;

#include "d:/yaz180.h"

;==============================================================================
;
; DEFINES SECTION
;

;   from Nascom Basic Symbol Tables .ORIG $0390
DEINT       .EQU    $0C47       ; Function DEINT to get USR(x) into DE registers
ABPASS      .EQU    $13BD       ; Function ABPASS to put output into AB register

program     .equ    $4000       ; Where this program will exist
location    .equ    $3000       ; Where this driver will exist

;------------------------------------------------------------------
;
; IDE reg: A0-A2: /CS0: /CS1: Use:
;
;       $0    000    0    1     IDE Data Port
;       $1    001    0    1     Read: Error code (also see $$)
;       $2    010    0    1     Number Of Sectors To Transfer
;       $3    011    0    1     Sector address LBA 0 (0:7)
;       $4    100    0    1     Sector address LBA 1 (8:15)
;       $5    101    0    1     Sector address LBA 2 (16:23)
;       $6    110    0    1     Head Register, Sector address LBA 3 (24:27) (also see **)
;       $7    111    0    1     Read: "Status", Write: Issue command (also see ##)
;       $8    000    1    0     Not Important
;       $9    001    1    0     Not Important
;       $A    010    1    0     Not Important
;       $B    011    1    0     Not Important
;       $C    100    1    0     Not Important
;       $D    101    1    0     Not Important
;       $E    110    1    0     2nd Status, Interrupt, and Reset
;       $F    111    1    0     Active Status Register 
;
;       $$ Bits in Error Register $1
;
;       Bit 7   = BBK   Bad Block Detected
;       Bit 6   = UNC   Uncorrectable Error
;       Bit 5   = MC    No media
;       Bit 4   = IDNF  Selector Id
;       Bit 3   = MCR   Media Change requested
;       Bit 2   = ABRT  Indecent Command - Doh!
;       Bit 1   = TK0NF Track 0 unavailable -> Trash
;       Bit 0   = AMNF  Address mark not found

;       ** Bits in LBA 3 Register $6:
;
;       Bit 7   = Always set to 1
;       Bit 6   = Always Set to 1 for LBA Mode Access
;       Bit 5   = Always set to 1
;       Bit 4   = Select Master (0) or Slave (1) drive
;       Bit 0:3 = LBA bits (24:27)
;
;       ## Bits in Command / Status Register $7:
;
;       Bit 7   = BSY   1=busy, 0=not busy
;       Bit 6   = RDY   1=ready for command, 0=not ready yet
;       Bit 5   = DWF   1=fault occured inside drive
;       Bit 4   = DSC   1=seek complete
;       Bit 3   = DRQ   1=data request ready, 0=not ready to xfer yet
;       Bit 2   = ECC   1=correctable error occured
;       Bit 1   = IDX   vendor specific
;       Bit 0   = ERR   1=error occured

;------------------------------------------------------------------------------
; Hardware Configuration

; 8255 PIO chip.  Change these to specify where the PIO is addressed,
; and which of the 8255's ports are connected to which ide signals.
; The first three control which 8255 ports have the control signals,
; upper and lower data bytes.  The last two are mode setting for the
; 8255 to configure its ports, which must correspond to the way that
; the first three lines define which ports are connected.
PIO_IDE_LSB     .equ    PIOA        ;IDE lower 8 bits
PIO_IDE_MSB     .equ    PIOB        ;IDE upper 8 bits
PIO_IDE_CTL     .equ    PIOC        ;IDE control lines
PIO_IDE_CONFIG  .equ    PIOCNTL     ;PIO configuration
PIO_IDE_RD      .equ    PIOCNTL10   ;PIO_IDE_CTL out, PIO_IDE_LSB/MSB input
PIO_IDE_WR      .equ    PIOCNTL00   ;all PIO ports output

; IDE control lines for use with PIO_IDE_CTL. Change these 8
; constants to reflect where each signal of the 8255 each of the
; IDE control signals is connected.  All the control signals must
; be on the same port, but these 8 lines let you connect them to
; whichever pins on that port.
IDE_A0_LINE     .equ    $10        ;direct from 8255 to ide interface
IDE_A1_LINE     .equ    $04        ;direct from 8255 to ide interface
IDE_A2_LINE     .equ    $40        ;direct from 8255 to ide interface
IDE_CS0_LINE    .equ    $08        ;inverter between 8255 and ide interface
IDE_CS1_LINE    .equ    $20        ;inverter between 8255 and ide interface
IDE_WR_LINE     .equ    $01        ;inverter between 8255 and ide interface
IDE_RD_LINE     .equ    $02        ;inverter between 8255 and ide interface
IDE_RST_LINE    .equ    $80        ;inverter between 8255 and ide interface


;------------------------------------------------------------------------------
; IDE I/O Register Addressing
;

; IDE control lines for use with PIO_IDE_CTL. Symbolic constants
; for the IDE registers, which makes the code more readable than
; always specifying the address pins
IDE_DATA        .equ    IDE_CS0_LINE
IDE_ERROR       .equ    IDE_CS0_LINE + IDE_A0_LINE
IDE_SEC_CNT     .equ    IDE_CS0_LINE + IDE_A1_LINE  ;Typically 1 Sector only
IDE_SECTOR      .equ    IDE_CS0_LINE + IDE_A1_LINE + IDE_A0_LINE    ;LBA0
IDE_CYL_LSB     .equ    IDE_CS0_LINE + IDE_A2_LINE                  ;LBA1
IDE_CYL_MSB     .equ    IDE_CS0_LINE + IDE_A2_LINE + IDE_A0_LINE    ;LBA2
IDE_HEAD        .equ    IDE_CS0_LINE + IDE_A2_LINE + IDE_A1_LINE    ;LBA3
IDE_COMMAND     .equ    IDE_CS0_LINE + IDE_A2_LINE + IDE_A1_LINE + IDE_A0_LINE
IDE_STATUS      .equ    IDE_CS0_LINE + IDE_A2_LINE + IDE_A1_LINE + IDE_A0_LINE

IDE_CONTROL     .equ    IDE_CS1_LINE + IDE_A2_LINE + IDE_A1_LINE
IDE_ALT_STATUS  .equ    IDE_CS1_LINE + IDE_A2_LINE + IDE_A1_LINE

IDE_LBA0        .equ    IDE_CS0_LINE + IDE_A1_LINE + IDE_A0_LINE    ;SECTOR
IDE_LBA1        .equ    IDE_CS0_LINE + IDE_A2_LINE                  ;CYL_LSB
IDE_LBA2        .equ    IDE_CS0_LINE + IDE_A2_LINE + IDE_A0_LINE    ;CYL_MSB
IDE_LBA3        .equ    IDE_CS0_LINE + IDE_A2_LINE + IDE_A1_LINE    ;HEAD

; IDE Command Constants.  These should never change.
IDE_CMD_RECAL       .equ    $10 ;recalibrate the disk, wait for ready status
IDE_CMD_READ        .equ    $20 ;read with retry - $21 read no retry
IDE_CMD_WRITE       .equ    $30 ;write with retry - $31 write no retry
IDE_CMD_INIT        .equ    $91 ;initialize drive parameters

IDE_CMD_SPINDOWN    .equ    $E0 ;immediate ide_spindown of disk
IDE_CMD_SPINUP      .equ    $E1 ;immediate ide_spinup of disk
IDE_CMD_POWERDOWN   .equ    $E2 ;auto powerdown - sector count 5 sec units
IDE_CMD_CACHE_FLUSH .equ    $E7 ;flush hardware write cache
IDE_CMD_ID          .equ    $EC ;identify drive

;==============================================================================
;
; VARIABLES SECTION
;

;IDE Status byte
    ;set bit 0 : User selects master (0) or slave (1) drive
    ;bit 1 : Flag 0 = master not previously accessed 
    ;bit 2 : Flag 0 = slave not previously accessed
idestatus   .equ    Z180_VECTOR_BASE+Z180_VECTOR_SIZE+$30    


;IDE 512 byte sector buffer origin
ide_buffer  .equ    APUPTRBuf+APU_PTR_BUFSIZE+1

;==============================================================================
;
; CODE SECTION
;

;------------------------------------------------------------------------------
; Main Program, a simple test.

    .org program

begin:
    ld (STACKTOP), sp
    ld sp, STACKTOP

    ld hl, msg_1            ;print a welcome message
    call pstr 

    ;reset the drive
    call ide_hard_reset

    ;reset the drive
    call ide_soft_reset

    ;initialize the drive. If there is no drive, this may hang
    call ide_init
    
    ;cause the drive to spin up
    call ide_spinup

    ;get the drive id info. If there is no drive, this may hang
    ld hl, ide_buffer       ;put the data into this buffer
    call ide_drive_id

    ;print the drive's model number
    ld hl, msg_mdl
    call pstr
    ld hl, ide_buffer + 54
    ld b, 20
    call print_name
    call pnewline

    ;print the drive's serial number
    ld hl, msg_sn
    call pstr
    ld hl, ide_buffer + 20
    ld b, 10
    call print_name
    call pnewline

    ;print the drive's firmware revision string
    ld hl, msg_rev
    call pstr
    ld hl, ide_buffer + 46
    ld b, 4
    call print_name
    call pnewline

    ;print the drive's cylinder, head, and sector specs
    ld hl, msg_cy
    call pstr
    ld hl, ide_buffer + 2
    call phex16
    ld hl, msg_hd
    call pstr
    ld hl, ide_buffer + 6
    call phex16
    ld hl, msg_sc
    call pstr
    ld hl, ide_buffer + 12
    call phex16
    call pnewline
    call pnewline

    ;dump the ID information
    ld hl, ide_buffer
    call phexdump

    xor a
dump_sector:
    ;read sector $00000000 to $000000FF
    ld bc, $0000
    ld de, $0000
    ld e, a
    ld hl, ide_buffer
    call ide_read_sector
    ;dump the $00000000 sector information
    ld hl, ide_buffer
    call phexdump
    inc a               ;print first 256 sectors, for fun
    jr nz, dump_sector
    
    ;cause the drive to spin down
    call ide_spindown

    ld sp, (STACKTOP)
    ret


msg_1:      .db     "IDE Disk Drive Test "
            .db     "Program",13,10,13,10,0
msg_mdl:    .db     "Model: ",0
msg_sn:     .db     "S/N:   ",0
msg_rev:    .db     "Rev:   ",0
msg_cy:     .db     "Cylinders: ", 0
msg_hd:     .db     ", Heads: ", 0
msg_sc:     .db     ", Sectors: ", 0

;------------------------------------------------------------------------------
; Extra print routines during testing

    ;print CR/LF
pnewline:
    ld a, CR
    rst 08
    ld a, LF
    rst 08
    ret

    ;print a string pointed to by HL, null terminated
pstr:
    ld a, (hl)          ; Get a byte
    or a                ; Is it null $00 ?
    ret z               ; Then RETurn on terminator
    rst 08              ; Print it
    inc hl              ; Next byte
    jr pstr

    ;print a string pointed to by HL, no more than B words long
    ;the IDE string are byte swapped.  Fetch each
    ;word and swap so the names print correctly
print_name:
    inc hl
    ld a, (hl)          ; Get LSB byte
    or a                ; Is it null $00 ?
    ret z               ; Then RETurn on terminator
    rst 08              ; Print it
    dec hl
    ld a, (hl)          ; Get MSB byte
    or a                ; Is it null $00 ?
    ret z               ; Then RETurn on terminator
    rst 08              ; Print it
    inc hl              ; Next byte
    inc hl
    djnz print_name     ; Continue until B = 00
    ret

    ;print contents of HL as 16 bit number in ASCII HEX
phex16:
    push af
    ld a, h
    call phex
    ld a, l
    call phex
    pop af
    ret

    ;print contents of A as 8 bit number in ASCII HEX
phex:
    push af             ;store the binary value
    rlca                ;shift accumulator left by 4 bits
    rlca
    rlca
    rlca
    and $0F             ;now high nibble is low position
    cp 10
    jr c, phex_b        ;jump if high nibble < 10
    add a, 7            ;otherwise add 7 before adding '0'
phex_b:
    add a, '0'          ;add ASCII 0 to make a character
    rst 08              ;print high nibble
    pop af              ;recover the binary value
phex1:
    and $0F
    cp 10
    jr c, phex_c        ;jump if low nibble < 10
    add a, 7
phex_c:
    add a, '0'
    rst 08              ;print low nibble
    ret


    ;print a hexdump of the data in the 512 byte buffer HL
phexdump:
    push af
    push bc
    push hl
    call pnewline
    ld c, 32            ;print 32 lines
phd1:
    xor a               ;print address, starting at zero
    ld h, a
    call phex16
    ld a, ':'
    rst 08
    ld a, ' '
    rst 08

    ld b, 16            ;print 16 hex bytes per line
    pop hl
    push hl    
phd2:
    ld a, (hl)
    inc hl
    call phex           ;print each byte in hex
    ld    a, ' '
    rst 08
    djnz phd2

    ld    a, ' '
    rst 08
    ld    a, ' '
    rst 08
    ld    a, ' '
    rst 08

    pop hl
    ld b, 16            ;print 16 ascii words per line
phd3:
    ld a, (hl)
    inc hl
    and $7f             ;only 7 bits for ascii
    tst $7F
    jr nz, phd3b
    xor a               ;avoid 127/255 (delete/rubout) char
phd3b:
    cp $20
    jr nc, phd3c
    xor a               ;avoid control characters
phd3c:
    rst 08
    djnz phd3
    
    call pnewline
    push hl
    dec c
    jr nz, phd1

    call pnewline
    pop hl
    pop bc
    pop af
    ret

;------------------------------------------------------------------------------
; Routines that talk with the IDE drive, these should be called by
; the main program.

    .org location

    ;read a sector
    ;LBA specified by the 4 bytes in BCDE
    ;the address of the buffer to fill is in HL
    ;return carry on success, no carry for an error
ide_read_sector:
    push af
    call ide_wait_ready     ;make sure drive is ready
    ret nc
    call ide_setup_lba      ;tell it which sector we want in BCDE
    ld a, IDE_COMMAND
    ld e, IDE_CMD_READ
    call ide_write_byte     ;ask the drive to read it
    call ide_wait_ready     ;make sure drive is ready to proceed
    ret nc
    call ide_test_error     ;ensure no error was reported
    ret nc
    call ide_wait_drq       ;wait until it's got the data
    ret nc
    call ide_read_block     ;grab the data into (HL++)
    pop af
    scf                     ;carry = 1 on return = operation ok
    ret

    ;write a sector
    ;specified by the 4 bytes in BCDE
    ;the address of the origin buffer is in HL
    ;return carry on success, no carry for an error
ide_write_sector:
    push af
    call ide_wait_ready     ;make sure drive is ready
    ret nc
    call ide_setup_lba      ;tell it which sector we want in BCDE
    ld a, IDE_COMMAND
    ld e, IDE_CMD_WRITE
    call ide_write_byte     ;instruct drive to write a sector
    call ide_wait_ready     ;make sure drive is ready to proceed
    ret nc
    call ide_test_error     ;ensure no error was reported
    ret nc
    call ide_wait_drq       ;wait unit it wants the data
    ret nc
    call ide_write_block    ;send the data to the drive from (HL++)
    call ide_wait_ready
    ret nc
    call ide_test_error     ;ensure no error was reported
    ret nc
    ld a, IDE_COMMAND
    ld e, IDE_CMD_CACHE_FLUSH
    call ide_write_byte     ;tell drive to flush its hardware cache
    call ide_wait_ready     ;wait until the write is complete
    ret nc
    call ide_test_error     ;ensure no error was reported
    ret nc
    pop af
    scf                     ;carry = 1 on return = operation ok
    ret

;------------------------------------------------------------------------------

    ;do the identify drive command, and return with the ide_buffer
    ;filled with info about the drive.
    ;the buffer to fill is in HL
ide_drive_id:
    push af
    push de
    call ide_wait_ready
    ret nc
    ld e, 11100000b
    ld a, IDE_HEAD
    call ide_write_byte     ;select the master device, LBA mode
    call ide_wait_ready
    ret nc
    ld e, IDE_CMD_ID    
    ld a, IDE_COMMAND
    call ide_write_byte     ;issue the command
    call ide_wait_ready     ;make sure drive is ready to proceed
    ret nc
    call ide_test_error     ;ensure no error was reported
    ret nc
    call ide_wait_drq       ;wait until it's got the data
    ret nc
    call ide_read_block     ;grab the data buffer in (HL++)
    pop de
    pop af
    scf                     ;carry = 1 on return = operation ok
    ret

;------------------------------------------------------------------------------

    ;tell the drive to spin down
ide_spindown:
    push af
    push de
    call ide_wait_ready
    ret nc
    ld e, IDE_CMD_SPINDOWN
    jr ide_spin2

    ;tell the drive to spin up
ide_spinup:
    push af
    push de
    call ide_wait_ready
    ret nc
    ld e, IDE_CMD_SPINUP

ide_spin2:
    ld    a, IDE_COMMAND
    call ide_write_byte
    call ide_wait_ready
    ret nc
    pop de 
    pop af
    ret

;------------------------------------------------------------------------------

    ;initialize the ide drive
ide_init:
    push af
    push de
    xor a
    ld (idestatus), a   ;set master device
    ld e, 11100000b
    ld a, IDE_HEAD
    call ide_write_byte ;select the master device, LBA mode
    call ide_wait_ready
    ret nc
    ld e, IDE_CMD_INIT  ;needed for old drives
    ld a, IDE_COMMAND
    call ide_write_byte ;do init parameters command
    pop de
    pop af
    jp ide_wait_ready

;------------------------------------------------------------------------------

    ;by writing to the IDE_CONTROL register, a software reset
    ;can be initiated.
    ;this should be followed with a call to "ide_init".
ide_soft_reset:
    push af
    push de
    ld e, 00000110b     ;no interrupt, set drives reset
    ld a, IDE_CONTROL
    call ide_write_byte
    ld e, 00000010b     ;no interrupt, clear drives reset
    ld a, IDE_CONTROL    
    call ide_write_byte
    pop de
    pop af
    jp ide_wait_ready

;------------------------------------------------------------------------------

    ;do a hard reset on the drive, by pulsing its reset pin.
    ;do this first, and if a soft reset doesn't work.
    ;this should be followed with a call to "ide_init".
ide_hard_reset:
    push af
    push bc
    ld bc, PIO_IDE_CONFIG
    ld a, PIO_IDE_RD
    out (c), a          ;config 8255 chip, read mode
    ld bc, PIO_IDE_CTL
    ld a, IDE_RST_LINE
    out (c),a           ;hard reset the disk drive
    ld b, $0
ide_rst_dly:
    djnz ide_rst_dly    ;delay 256 nop 150us (reset minimum 25us)
    ld bc, PIO_IDE_CTL
    xor a
    out (c),a           ;no ide control lines asserted
    pop bc
    pop af
    ret

;------------------------------------------------------------------------------
; IDE internal subroutines 
;
; These routines talk to the drive, using the low level I/O.
; Normally a program should not call these directly.
;------------------------------------------------------------------------------

    ;How to poll (waiting for the drive to be ready to transfer data):
    ;Read the Regular Status port until bit 7 (BSY, value = 0x80) clears,
    ;and bit 3 (DRQ, value = 0x08) sets.
    ;Or until bit 0 (ERR, value = 0x01) or bit 5 (DFE, value = 0x20) sets.
    ;If neither error bit is set, the device is ready right then.

    ;Carry is set on wait success.
ide_wait_ready:
    push af
ide_wait_ready2:
    ld a, IDE_ALT_STATUS    ;get IDE alt status register
    call ide_read_byte
    or a                    ;carry 0
    tst 00100001b           ;test for ERR or DFE
    jr nz, ide_wait_error
    and 11000000b           ;mask off BuSY and RDY bits
    xor 01000000b           ;wait for RDY to be set and BuSY to be clear
    jr nz, ide_wait_ready2
    pop af
    scf                     ;set carry flag on success
    ret

    ;Wait for the drive to be ready to transfer data.
    ;Returns the drive's status in A
    ;Carry is set on wait success.
ide_wait_drq:
    push af
ide_wait_drq2:
    ld a, IDE_ALT_STATUS    ;get IDE alt status register
    call ide_read_byte
    or a                    ;carry 0
    tst 00100001b           ;test for ERR or DFE
    jr nz, ide_wait_error
    and 10001000b           ;mask off BuSY and DRQ bits
    xor 00001000b           ;wait for DRQ to be set and BuSY to be clear
    jr nz, ide_wait_drq2
ide_test_success:
    pop af
    scf                     ;set carry flag on success
    ret

ide_wait_error:
    pop af
    or a                    ;clear carry flag on failure
    ret

    ;load the IDE status register and if there is an error noted,
    ;then load the IDE error register to provide details.
    ;Carry is set on no error.
ide_test_error:
    push af
    ld a, IDE_ALT_STATUS    ;select status register
    call ide_read_byte      ;get status in A
    bit 0, a                ;test ERR bit
    jr z, ide_test_success
    bit 5, a
    jr nz, ide_test2        ;test write error bit
    
    ld a, IDE_ERROR         ;select error register
    call ide_read_byte      ;get error register in A
ide_test2:
    or a                    ;make carry flag zero = error!
    inc sp                  ;pop old af
    inc sp
    ret                     ;if a = 0, ide write busy timed out

;-----------------------------------------------------------------------------
    ;set up the drive LBA registers
    ;LBA is contained in BCDE registers
ide_setup_lba:
    push af
    push hl
    ld a, IDE_LBA0
    call ide_write_byte     ;set LBA0 0:7
    ld e, d
    ld a, IDE_LBA1
    call ide_write_byte     ;set LBA1 8:15
    ld e, c
    ld a, IDE_LBA2
    call ide_write_byte     ;set LBA2 16:23
    ld a, b
    and 00001111b           ;lowest 4 bits used only
    or  11100000b           ;to enable LBA address mode
    ld hl, idestatus        ;set bit 4 accordingly
    bit 0, (hl)
    jr z, ide_setup_master
    or $10                  ;if it is a slave, set that bit
ide_setup_master:
    ld e, a
    ld a, IDE_LBA3
    call ide_write_byte     ;set LBA3 24:27 + bits 5:7=111
    ld e, $1
    ld a, IDE_SEC_CNT    
    call ide_write_byte     ;set sector count to 1
    pop hl
    pop af
    ret

;------------------------------------------------------------------------------
; Low Level I/O
; These routines talk directly to the drive, via the 8255 chip.
;------------------------------------------------------------------------------

    ;Read a block of 512 bytes (one sector) from the drive
    ;16 bit data register and store it in memory at (HL++)
ide_read_block:
    push bc
    push de
    ld bc, PIO_IDE_CTL
    ld d, IDE_DATA    
    out (c), d              ;drive address onto control lines
    ld e, $0                ;keep iterative count in e
ide_rdblk2:
    ld d, IDE_DATA|IDE_RD_LINE
    out (c), d              ;and assert read pin
    ld bc, PIO_IDE_LSB
    ini                     ;read the lower byte (HL++)
    ld bc, PIO_IDE_MSB
    ini                     ;read the upper byte (HL++)
    ld bc, PIO_IDE_CTL
    ld d, IDE_DATA
    out (c), d              ;deassert read pin
    dec e                   ;keep iterative count in e
    jr nz, ide_rdblk2
   ;ld bc, PIO_IDE_CTL      ;just for info
    ld d, $0
    out (c), d              ;deassert all control pins
    pop de
    pop bc
    ret


    ;Write a block of 512 bytes (one sector) from (HL++) to
    ;the drive 16 bit data register
ide_write_block:
    push bc
    push de
    ld bc, PIO_IDE_CONFIG
    ld d, PIO_IDE_WR
    out (c), d              ;config 8255 chip, write mode
    ld bc, PIO_IDE_CTL
    ld d, IDE_DATA
    out (c), d              ;drive address onto control lines
    ld e, $0                ;keep iterative count in e
ide_wrblk2: 
    ld bc, PIO_IDE_CTL|IDE_WR_LINE
    out (c), d              ;and assert write pin
    ld bc, PIO_IDE_LSB      ;drive lower lines with lsb
    outi                    ;write the lower byte (HL++)
    ld bc, PIO_IDE_MSB      ;drive upper lines with msb
    outi                    ;write the upper byte (HL++)
    ld bc, PIO_IDE_CTL
    ld d, IDE_DATA
    out (c), d              ;deassert write pin
    dec e                   ;keep iterative count in e
    jr nz, ide_wrblk2
   ;ld bc, PIO_IDE_CTL      ;just for info
    ld d, $0
    out (c), d              ;deassert all control pins
    ld bc, PIO_IDE_CONFIG
    ld d, PIO_IDE_RD
    out (c), d              ;config 8255 chip, read mode
    pop de
    pop bc
    ret

    ;Do a read bus cycle to the drive, using the 8255.
    ;input A = ide register address
    ;output A = lower byte read from IDE drive
ide_read_byte:
    push bc
    push de
    ld d, a                 ;copy address to D
    ld bc, PIO_IDE_CTL
    out (c), a              ;drive address onto control lines
    or IDE_RD_LINE    
    out (c), a              ;and assert read pin
    ld bc, PIO_IDE_LSB
    in e, (c)               ;read the lower byte
    ld bc, PIO_IDE_CTL
    out (c), d              ;deassert read pin
    xor a
    out (c), a              ;deassert all control pins
    ld a, e
    pop de
    pop bc
    ret

    ;Do a write bus cycle to the drive, via the 8255
    ;input A = ide register address
    ;input E = lsb to write to IDE drive
    ;uses DE
ide_write_byte:
    push bc
    ld d, a                 ;copy address to D (unused MSB)
    ld bc, PIO_IDE_CONFIG
    ld a, PIO_IDE_WR
    out (c), a              ;config 8255 chip, write mode
    ld bc, PIO_IDE_CTL
    ld a, d    
    out (c), a              ;drive address onto control lines
    or IDE_WR_LINE    
    out (c), a              ;and assert write pin
    ld bc, PIO_IDE_LSB
    out (c), e              ;drive lower lines with lsb
    ld bc, PIO_IDE_CTL
    out (c), d              ;deassert write pin
    xor a
    out (c), a              ;deassert all control pins
    ld bc, PIO_IDE_CONFIG
    ld a, PIO_IDE_RD
    out (c), a              ;config 8255 chip, read mode
    pop bc
    ret

    .end
