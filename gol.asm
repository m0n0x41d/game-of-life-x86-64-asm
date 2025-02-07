; Game of Life - Assembly Implementation
; Author: Ivan Zakutnii
; Date: 2025-02-07
; License: MIT License
;
; Game of Life with predefined patterns implementation
; Features:
; - Interactive menu system
; - Multiple patterns (glider, blinker, block, beacon)
; - Configurable board size
; - Color support
; - Speed control
; - Pause/resume functionality

section .data
    ; Game settings
    max_width   equ 100     ; Max board width
    max_height  equ 100     ; Max board height
    def_width   equ 40      ; Default width
    def_height  equ 20      ; Default height

    ; Terminal control constants
    TCGETS     equ 0x5401   ; Get terminal settings
    TCSETS     equ 0x5402   ; Set terminal settings
    ICANON     equ 0o0000002
    ECHO       equ 0o0000010

    ; Game state variables
    align 8
    width        dq def_width
    height       dq def_height
    gen_count    dq 0        ; Current generation
    alive_count  dq 0        ; Number of live cells
    is_paused    db 0        ; Pause flag
    use_colors   db 1        ; Color display flag
    current_pattern db 0     ; Active pattern ID
    input_buffer    db 0     ; Keyboard input

    ; Speed settings (in nanoseconds)
    align 8
    min_delay   dq 100000000   ; 100ms (fastest)
    max_delay   dq 500000000   ; 500ms (slowest)
    delay_step  dq 100000000   ; 100ms increment
    
    ; Terminal settings structures
    align 8
    termios_orig:
        times 60 db 0   ; Space for original terminal settings
    termios_raw:
        times 60 db 0   ; Space for raw mode settings
    
    ; Poll structure
    align 8
    poll_fd:
        dd 0            ; fd
        dw 0x001        ; events (POLLIN)
        dw 0            ; revents
    
    ; Timespec structure
    align 8
    timespec:
        dq 0              ; Seconds
        dq 400000000      ; Nanoseconds (400ms default)

    ; ANSI escape sequences
    clear_seq     db 27, "[2J", 27, "[H", 0    ; Renamed from clear_screen
    enter_alt_screen db 27, "[?1049h", 0
    exit_alt_screen  db 27, "[?1049l", 0
    hide_cursor     db 27, "[?25l", 0
    show_cursor     db 27, "[?25h", 0
    color_green     db 27, "[32m", 0
    color_reset     db 27, "[0m", 0

    ; Game display characters
    alive_char   db "##", 0
    dead_char    db "  ", 0
    border_h     db "--", 0
    border_v     db "| ", 0
    newline      db 10, 0

    ; Status messages
    status_gen    db "Generation: ", 0
    status_alive  db " | Alive: ", 0
    status_speed  db " | Speed: ", 0
    status_paused db " | PAUSED", 0
    speed_star    db "*", 0

    ; Menu text
    menu_header  db "Game of Life", 10, 10, 0
    menu_options db "1. Start Game", 10
                db "2. Select Pattern", 10
                db "3. Change Size", 10
                db "4. Toggle Colors", 10
                db "5. Help", 10
                db "6. Exit", 10, 10
                db "Select option (1-6): ", 0

    pattern_menu db "Select pattern:", 10
                db "1. Glider (moves diagonally)", 10
                db "2. Blinker (oscillates)", 10
                db "3. Block (it is just an immortal block)", 10
                db "4. Beacon (oscillates)", 10
                db "Choice (1-4): ", 0

    ; Error messages
    err_pattern  db "Invalid pattern selection!", 10, 0
    err_size     db "Invalid size! Must be between 10 and 100.", 10, 0
    err_syscall  db "System call failed!", 10, 0

    ; Help text
    controls_info db 10, "Controls during game:", 10
                 db "  P - Pause/Resume", 10
                 db "  U - Speed up", 10
                 db "  D - Slow down", 10
                 db "  Q - Quit to menu", 10
                 db "  Ctrl+C - Exit program", 10, 10, 0

    ; Pre-defined patterns (coordinates format: x,y pairs)
    pattern_glider   db 1,0, 2,1, 0,2, 1,2, 2,2, 0  ; Null-terminated
    pattern_blinker  db 0,0, 1,0, 2,0, 0
    pattern_block    db 0,0, 1,0, 0,1, 1,1, 0
    pattern_beacon   db 0,0, 1,0, 0,1, 2,2, 3,2, 2,3, 3,3, 0
    
    align 8
    short_delay:
        dq 0              ; Seconds
        dq 200000000      ; Nanoseconds (200ms)

    ; Add clear sequence
    clear       db 27, "[2J", 27, "[H", 0  ; Clear screen and move cursor to home
    clear_len   equ $ - clear

    align 8
    pattern_jumps:
        dq load_glider
        dq load_blinker
        dq load_block
        dq load_beacon

    ; Structure for pattern definitions
    align 8
    pattern_defs:
        ; Glider pattern
        glider_width  dq 3
        glider_height dq 3
        glider_data   db 0,1,0
                      db 0,0,1
                      db 1,1,1
        
        ; Add more patterns...

    ; Signal handling constants
    SIGINT      equ 2
    SA_RESTORER equ 0x04000000    ; Linux signal handling constant
    
    ; Game settings messages
    prompt_width    db "Enter new width (10-100): ", 0
    prompt_height   db "Enter new height (10-100): ", 0
    msg_colors_on   db "Colors enabled", 10, 0
    msg_colors_off  db "Colors disabled", 10, 0
    
    ; Game dimensions limits
    min_width   equ 10
    min_height  equ 10
    
    ; Speed variable (if not already defined elsewhere)
    align 8
    speed       dq 200000000  ; Default speed in nanoseconds
    
    ; Signal handling structure
    align 8
    sigaction:
        dq signal_handler    ; sa_handler
        dq SA_RESTORER      ; sa_flags
        dq signal_restorer   ; sa_restorer
        times 16 dq 0       ; sa_mask

section .bss
    ; Game boards
    align 8
    current_gen: resb max_width * max_height
    next_gen:    resb max_width * max_height

section .text
global _start

_start:
    ; Initialize program state
    call init_program
    
main:
    push rbp
    mov rbp, rsp
    sub rsp, 16     ; Allocate some stack space for local variables
    
.menu_loop:
    call clear_screen
    
    ; Display menu
    lea rsi, [rel menu_header]
    call print_string
    lea rsi, [rel menu_options]
    call print_string
    
    ; Get menu choice
    call get_input
    
    ; Convert input to number
    movzx rax, byte [input_buffer]
    sub rax, '0'
    
    ; Process menu choice
    cmp rax, 1
    je .start_game_wrapper
    cmp rax, 2
    je .call_select_pattern
    cmp rax, 3
    je .call_change_size
    cmp rax, 4
    je .call_toggle_colors
    cmp rax, 5
    je .call_show_help
    cmp rax, 6
    je .call_exit_program
    jmp .menu_loop
    
.start_game_wrapper:
    call start_game
    test rax, rax        ; Check return value
    jmp .menu_loop
    
.call_select_pattern:
    call select_pattern
    jmp .menu_loop
.call_change_size:
    call change_size
    jmp .menu_loop
.call_toggle_colors:
    call toggle_colors
    jmp .menu_loop
.call_show_help:
    call show_help
    jmp .menu_loop
.call_exit_program:
    add rsp, 16          ; Clean up stack space
    leave
    jmp exit_program

; Initialize program state
init_program:
    push rbp
    mov rbp, rsp
    
    ; Switch to alternate screen buffer
    lea rsi, [rel enter_alt_screen]
    call print_string
    
    ; Set up signal handler for SIGINT
    mov rax, 13         ; rt_sigaction
    mov rdi, SIGINT     ; signal number (SIGINT = 2)
    lea rsi, [rel sigaction]  ; new handler
    xor rdx, rdx        ; old handler (NULL)
    mov r10, 8          ; sigsetsize
    syscall
    
    mov byte [is_paused], 0
    mov byte [use_colors], 1
    mov byte [current_pattern], 1    ; Set default pattern to glider
    mov qword [gen_count], 0
    mov qword [alive_count], 0
    
    ; Clear both generations
    call clear_boards
    
    ; Set default pattern (glider)
    call load_glider
    
    leave
    ret

; Clear screen using ANSI escape sequence
clear_screen:
    push rbp
    mov rbp, rsp
    
    lea rsi, [rel clear_seq]    ; Use renamed clear sequence
    call print_string
    
    leave
    ret

; Show main menu
show_menu:
    push rbp
    mov rbp, rsp
    
    lea rsi, [rel menu_header]
    call print_string
    lea rsi, [rel menu_options]
    call print_string
    
    leave
    ret

; Get user input
get_input:
    push rbp
    mov rbp, rsp
    
    ; Clear input buffer first
    mov rcx, 16
    xor rax, rax
    lea rdi, [rel input_buffer]
    rep stosb
    
    mov rax, 0          ; sys_read
    mov rdi, 0          ; stdin
    lea rsi, [rel input_buffer]
    mov rdx, 16
    syscall
    
    ; Ensure null termination
    cmp rax, 16
    jge .limit_input
    mov byte [input_buffer + rax - 1], 0  ; Remove newline
    jmp .done
    
.limit_input:
    mov byte [input_buffer + 15], 0

.done:
    leave
    ret

; Set terminal to raw mode
set_raw_mode:
    push rbp
    mov rbp, rsp
    
    ; Get current terminal settings
    mov rax, 16         ; sys_ioctl
    mov rdi, 0          ; stdin
    mov rsi, TCGETS
    lea rdx, [rel termios_orig]
    syscall
    
    ; Copy settings to raw mode structure
    mov rcx, 60
    lea rsi, [rel termios_orig]
    lea rdi, [rel termios_raw]
    rep movsb
    
    ; Modify settings for raw mode
    lea rax, [rel termios_raw + 12]
    mov dword [rax], 0  ; Clear local mode flags
    
    ; Apply new settings
    mov rax, 16         ; sys_ioctl
    mov rdi, 0          ; stdin
    mov rsi, TCSETS
    lea rdx, [rel termios_raw]
    syscall
    
    leave
    ret

; Restore original terminal settings
restore_terminal:
    push rbp
    mov rbp, rsp
    
    ; Reset colors
    lea rsi, [rel color_reset]
    call print_string
    
    ; Show cursor
    lea rsi, [rel show_cursor]
    call print_string
    
    ; Return to main screen
    lea rsi, [rel exit_alt_screen]
    call print_string
    
    ; Restore terminal settings
    call restore_terminal
    
    leave
    ret

; Start game simulation
start_game:
    push rbp
    mov rbp, rsp
    
    ; Save registers we'll use
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Set raw mode before anything else
    call set_raw_mode
    
    ; Initialize game state
    mov qword [gen_count], 0
    mov byte [is_paused], 0
    mov byte [input_buffer], 0
    
.game_loop:
    call clear_screen
    call display_status
    call display_board
    
    cmp byte [is_paused], 0
    jne .check_input
    
    call update_generation
    inc qword [gen_count]
    
.check_input:
    ; Check for input without blocking
    mov dword [poll_fd], 0          ; stdin
    mov word [poll_fd + 4], 0x001   ; POLLIN
    mov word [poll_fd + 6], 0       ; revents
    
    mov rax, 7          ; sys_poll
    lea rdi, [rel poll_fd]
    mov rsi, 1          ; nfds
    mov rdx, 1          ; timeout = 1ms
    syscall
    
    test rax, rax
    jle .no_input       ; No input or error
    
    ; Read input
    mov rax, 0          ; sys_read
    mov rdi, 0          ; stdin
    lea rsi, [rel input_buffer]
    mov rdx, 1
    syscall
    
    ; Check for quit - do it first and separately
    cmp byte [input_buffer], 'q'
    je .return_to_menu
    
    ; Handle other inputs
    cmp byte [input_buffer], 'p'
    je .toggle_pause
    cmp byte [input_buffer], 'u'
    je .speed_up
    cmp byte [input_buffer], 'd'
    je .speed_down
    
.no_input:
    mov byte [input_buffer], 0
    
    ; Apply delay
    mov rax, 35         ; sys_nanosleep
    lea rdi, [rel timespec]
    xor rsi, rsi
    syscall
    
    jmp .game_loop

.return_to_menu:
    ; First restore terminal settings
    mov rax, 16         ; sys_ioctl
    mov rdi, 0          ; stdin
    mov rsi, TCSETS
    lea rdx, [rel termios_orig]
    syscall
    
    ; Clear the screen
    call clear_screen
    
    ; Reset colors if they were used
    lea rsi, [rel color_reset]
    call print_string
    
    ; Show cursor if it was hidden
    lea rsi, [rel show_cursor]
    call print_string
    
    ; Restore saved registers in reverse order
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    
    ; Clean up stack frame and return
    leave
    ret

.toggle_pause:
    xor byte [is_paused], 1
    jmp .no_input

.speed_up:
    mov rax, [timespec + 8]
    cmp rax, [min_delay]
    jle .no_input
    sub rax, [delay_step]
    mov [timespec + 8], rax
    jmp .no_input

.speed_down:
    mov rax, [timespec + 8]
    cmp rax, [max_delay]
    jge .no_input
    add rax, [delay_step]
    mov [timespec + 8], rax
    jmp .no_input

; Display game status
display_status:
    push rbp
    mov rbp, rsp
    push rax
    push rcx
    push rdx
    
    ; Display generation count
    lea rsi, [rel status_gen]
    call print_string
    mov rax, [gen_count]
    call print_number
    
    ; Display alive cells
    lea rsi, [rel status_alive]
    call print_string
    mov rax, [alive_count]
    call print_number
    
    ; Display speed indicator
    lea rsi, [rel status_speed]
    call print_string
    
    ; Convert delay to speed level (1-5)
    mov rax, [max_delay]
    sub rax, [timespec + 8]
    mov rcx, [delay_step]
    xor rdx, rdx
    div rcx
    inc rax             ; Speed level from 1 to 5
    
    ; Display speed stars
    mov rcx, rax        ; Counter for stars
.print_stars:
    lea rsi, [rel speed_star]
    call print_string
    dec rcx
    jnz .print_stars
    
    ; Display pause status if paused
    cmp byte [is_paused], 0
    je .status_done
    lea rsi, [rel status_paused]
    call print_string
    
.status_done:
    lea rsi, [rel newline]
    call print_string
    
    pop rdx
    pop rcx
    pop rax
    leave
    ret

; Display current board state
display_board:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    
    ; Reset alive counter
    mov qword [alive_count], 0
    
    ; Draw top border
    mov rcx, [width]
    lea rsi, [rel border_v]
    call print_string
.top_border:
    lea rsi, [rel border_h]
    call print_string
    dec rcx
    jnz .top_border
    lea rsi, [rel border_v]
    call print_string
    lea rsi, [rel newline]
    call print_string
    
    ; Draw board contents
    xor r12, r12        ; y counter
.row_loop:
    ; Draw left border
    lea rsi, [rel border_v]
    call print_string
    
    xor r13, r13        ; x counter
.col_loop:
    ; Calculate cell index
    mov rax, r12
    mul qword [width]
    add rax, r13
    
    ; Check bounds
    cmp rax, max_width * max_height
    jae .print_dead
    
    lea rbx, [rel current_gen]
    movzx rax, byte [rbx + rax]
    
    test rax, rax
    jz .print_dead
    
    inc qword [alive_count]
    
.print_alive:
    cmp byte [use_colors], 0
    je .skip_color
    
    lea rsi, [rel color_green]
    call print_string
    
.skip_color:
    lea rsi, [rel alive_char]
    call print_string
    
    cmp byte [use_colors], 0
    je .next_col
    
    lea rsi, [rel color_reset]
    call print_string
    jmp .next_col
    
.print_dead:
    lea rsi, [rel dead_char]
    call print_string
    
.next_col:
    inc r13
    cmp r13, [width]
    jl .col_loop
    
    ; Draw right border
    lea rsi, [rel border_v]
    call print_string
    lea rsi, [rel newline]
    call print_string
    
    inc r12
    cmp r12, [height]
    jl .row_loop
    
    ; Draw bottom border
    mov rcx, [width]
    lea rsi, [rel border_v]
    call print_string
.bottom_border:
    lea rsi, [rel border_h]
    call print_string
    dec rcx
    jnz .bottom_border
    lea rsi, [rel border_v]
    call print_string
    lea rsi, [rel newline]
    call print_string
    
    pop r13
    pop r12
    pop rbx
    leave
    ret

; Draw horizontal border
draw_horizontal_border:
    push rbp
    mov rbp, rsp
    push rcx
    
    lea rsi, [rel border_v]
    call print_string
    
    mov rcx, [width]
.border_loop:
    lea rsi, [rel border_h]
    call print_string
    dec rcx
    jnz .border_loop
    
    lea rsi, [rel border_v]
    call print_string
    lea rsi, [rel newline]
    call print_string
    
    pop rcx
    leave
    ret

; Update to next generation
update_generation:
    push rbp
    mov rbp, rsp
    
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Refresh
    mov rcx, max_width * max_height
    xor rax, rax
    lea rdi, [rel next_gen]
    rep stosb
    
    ; Process each cell
    xor r12, r12    ; y counter
.y_loop:
    xor r13, r13    ; x counter
.x_loop:
    ; Get neighbor count
    mov rdi, r13    ; x
    mov rsi, r12    ; y
    call count_neighbors
    mov r14, rax    ; save neighbor count
    
    ; Get current cell state
    mov rax, r12
    mul qword [width]
    add rax, r13
    lea rbx, [rel current_gen]
    movzx r15, byte [rbx + rax]  ; current state in r15
    
    ; Calculate target index in next generation
    lea rbx, [rel next_gen]
    add rbx, rax    ; rbx points to target cell
    
    ; Apply Game of Life rules
    test r15, r15
    jz .dead_cell
    
    ; Live cell rules
    cmp r14, 2
    jl .kill        ; Dies (< 2 neighbors)
    cmp r14, 3
    jle .live       ; Lives (2 or 3 neighbors)
    jmp .kill       ; Dies (> 3 neighbors)
    
.dead_cell:
    cmp r14, 3
    je .live        ; Born (exactly 3 neighbors)
    jmp .kill       ; Stays dead
    
.kill:
    mov byte [rbx], 0
    jmp .next_cell
    
.live:
    mov byte [rbx], 1
    
.next_cell:
    inc r13
    cmp r13, [width]
    jl .x_loop
    
    inc r12
    cmp r12, [height]
    jl .y_loop
    
    ; Copy next generation to current
    mov rcx, max_width * max_height
    lea rsi, [rel next_gen]
    lea rdi, [rel current_gen]
    rep movsb
    
    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    ret

; Count neighbors for cell at (x,y)
count_neighbors:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14
    push r15         ; Push registers individually
    
    ; Cache frequently used values in registers
    mov r12, [width]
    mov r13, [height]
    mov r14, rdi    ; x coordinate
    mov r15, rsi    ; y coordinate
    
    ; Parameters: rdi = x, rsi = y
    mov r12, rdi    ; x
    mov r13, rsi    ; y
    xor r15, r15    ; neighbor count
    
    ; Check all 8 neighboring cells
    mov r14d, -1    ; dy
.y_loop:
    mov ebx, -1     ; dx
.x_loop:
    ; Skip the center cell itself
    cmp r14d, 0
    jne .check_pos
    cmp ebx, 0
    je .next_x
    
.check_pos:
    ; Calculate neighbor x position with wrapping
    mov eax, r12d
    add eax, ebx
    
    ; Handle x wrapping
    cmp eax, 0
    jl .wrap_x_left
    cmp eax, [width]
    jge .wrap_x_right
    jmp .check_y_pos
    
.wrap_x_left:
    mov eax, [width]
    dec eax
    jmp .check_y_pos
    
.wrap_x_right:
    xor eax, eax
    
.check_y_pos:
    ; Calculate neighbor y position with wrapping
    mov ecx, r13d
    add ecx, r14d
    
    ; Handle y wrapping
    cmp ecx, 0
    jl .wrap_y_top
    cmp ecx, [height]
    jge .wrap_y_bottom
    jmp .check_cell
    
.wrap_y_top:
    mov ecx, [height]
    dec ecx
    jmp .check_cell
    
.wrap_y_bottom:
    xor ecx, ecx
    
.check_cell:
    ; Calculate cell index: y * width + x
    push rax
    mov eax, ecx
    mul dword [width]
    pop rcx
    add eax, ecx
    
    ; Check if cell is alive
    lea rsi, [rel current_gen]
    movzx eax, byte [rsi + rax]
    test eax, eax
    jz .next_x
    inc r15         ; Found a live neighbor
    
.next_x:
    inc ebx
    cmp ebx, 2
    jle .x_loop
    
    inc r14d
    cmp r14d, 2
    jle .y_loop
    
    ; Return neighbor count in rax
    mov rax, r15
    
    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12
    leave
    ret

; Check for keyboard input
check_keyboard:
    push rbp
    mov rbp, rsp
    
    ; Try to read a key without blocking
    mov rax, 0          ; sys_read
    mov rdi, 0          ; stdin
    lea rsi, [rel input_buffer]
    mov rdx, 1
    syscall
    
    test rax, rax       ; Check if we actually read anything
    jz .no_input
    
    movzx rax, byte [input_buffer]
    
    cmp al, 'p'         ; Toggle pause
    je .toggle_pause
    cmp al, 'u'         ; Changed from '+' to 'u'
    je .speed_up
    cmp al, 'd'         ; Changed from '-' to 'd'
    je .speed_down
    cmp al, 'q'         ; Quit
    je .quit_game
    jmp .done
    
.toggle_pause:
    xor byte [is_paused], 1
    jmp .done
    
.speed_up:
    mov rax, [speed]
    cmp rax, 50000000   ; Min delay 50ms
    jle .done
    sub rax, 50000000
    mov [speed], rax
    jmp .done
    
.speed_down:
    mov rax, [speed]
    cmp rax, 1000000000 ; Max delay 1000ms
    jge .done
    add rax, 50000000
    mov [speed], rax
    jmp .done

.quit_game:
    mov byte [input_buffer], 'q'
    jmp .done
    
.no_input:
    xor rax, rax
    
.done:
    leave
    ret

; Load glider pattern
load_glider:
    push rbp
    mov rbp, rsp
    push rbx
    
    ; Clear the board first
    call clear_boards
    
    ; Calculate center position
    mov rax, [height]
    shr rax, 1          ; height/2
    dec rax             ; Adjust for pattern size
    mul qword [width]   ; * width
    mov rbx, [width]
    shr rbx, 1          ; width/2
    dec rbx             ; Adjust for pattern size
    add rax, rbx        ; Add column offset
    
    ; Ensure we're not too close to edges
    cmp rax, 3
    jl .error
    mov rcx, [width]
    sub rcx, 3
    cmp rax, rcx
    jg .error
    
    lea rdi, [rel current_gen]
    add rdi, rax        ; rdi now points to center of board
    
    ; Place glider pattern:
    ;  #
    ; # #
    ;  ##
    mov byte [rdi + 1], 1                    ; Top row
    add rdi, [width]
    mov byte [rdi], 1                        ; Middle row
    mov byte [rdi + 2], 1
    add rdi, [width]
    mov byte [rdi + 1], 1                    ; Bottom row
    mov byte [rdi + 2], 1
    
    mov byte [current_pattern], 1
    pop rbx
    leave
    ret

.error:
    ; Handle error case - reset to safe position
    lea rdi, [rel current_gen]
    add rdi, max_width * 2 + 2   ; Safe position away from edges
    
    ; Place glider pattern at safe position
    mov byte [rdi + 1], 1
    add rdi, [width]
    mov byte [rdi], 1
    mov byte [rdi + 2], 1
    add rdi, [width]
    mov byte [rdi + 1], 1
    mov byte [rdi + 2], 1
    
    mov byte [current_pattern], 1
    pop rbx
    leave
    ret

; Clear both game boards
clear_boards:
    push rbp
    mov rbp, rsp
    
    ; Clear current generation
    mov rcx, max_width * max_height
    xor rax, rax
    lea rdi, [rel current_gen]
    rep stosb
    
    ; Clear next generation
    mov rcx, max_width * max_height
    lea rdi, [rel next_gen]
    rep stosb
    
    leave
    ret

; Print null-terminated string
print_string:
    push rbp
    mov rbp, rsp
    push rcx
    
    ; Get string length
    mov rcx, -1
    mov rdi, rsi
    mov al, 0
    repne scasb
    neg rcx
    dec rcx
    
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    mov rdx, rcx        ; length
    syscall
    
    pop rcx
    leave
    ret

; Print number in decimal
print_number:
    push rbp
    mov rbp, rsp
    push rbx
    
    mov rbx, 10         ; For division
    mov rcx, 0          ; Digit counter
    
.divide_loop:
    xor rdx, rdx        ; Clear for division
    div rbx
    push rdx            ; Save remainder
    inc rcx
    test rax, rax
    jnz .divide_loop
    
.print_loop:
    pop rax
    add al, '0'         ; Convert to ASCII
    mov [input_buffer], al
    
    push rcx
    mov rax, 1          ; sys_write
    mov rdi, 1          ; stdout
    lea rsi, [rel input_buffer]
    mov rdx, 1
    syscall
    pop rcx
    
    loop .print_loop
    
    pop rbx
    leave
    ret

; Exit program
exit_program:
    ; Reset terminal colors
    mov rax, 1
    mov rdi, 1
    lea rsi, [rel color_reset]
    mov rdx, 4
    syscall
    
    mov rax, 60         ; sys_exit
    xor rdi, rdi        ; status = 0
    syscall

; Select pattern menu
select_pattern:
    push rbp
    mov rbp, rsp
    
    call clear_screen
    
    ; Display pattern menu
    lea rsi, [rel pattern_menu]
    call print_string
    
    ; Get input
    call get_input
    
    ; Convert input to number and validate
    movzx rax, byte [input_buffer]
    sub rax, '0'
    
    ; Validate input range
    cmp rax, 1
    jl .invalid_pattern
    cmp rax, 4
    jg .invalid_pattern
    
    ; Jump table approach for pattern selection
    dec rax             ; Convert 1-based to 0-based index
    lea rdx, [rel pattern_jumps]
    mov rdx, [rdx + rax * 8]
    call rdx
    jmp .pattern_done
    
.invalid_pattern:
    lea rsi, [rel err_pattern]
    call print_string
    
.pattern_done:
    mov byte [input_buffer], 0    ; Clear input buffer
    leave
    ret

; Change board size
change_size:
    push rbp
    mov rbp, rsp
    push rbx    ; Save rbx as we'll use it
    
    call clear_screen
    
    ; Get width
    lea rsi, [rel prompt_width]
    call print_string
    call get_input
    
    ; Convert input to number
    xor rax, rax
    xor rbx, rbx    ; Use rbx as our running total
    lea rsi, [rel input_buffer]
.width_loop:
    movzx rdx, byte [rsi]
    cmp rdx, 0          ; Check for null terminator
    je .width_done
    cmp rdx, 10         ; Check for newline
    je .width_done
    cmp rdx, '0'        ; Check if below '0'
    jl .invalid_size
    cmp rdx, '9'        ; Check if above '9'
    jg .invalid_size
    
    sub rdx, '0'
    imul rbx, 10
    add rbx, rdx
    inc rsi
    jmp .width_loop
    
.width_done:
    mov rax, rbx
    cmp rax, min_width
    jl .invalid_size
    cmp rax, max_width
    jg .invalid_size
    
    mov [width], rax
    
    ; Get height
    lea rsi, [rel prompt_height]
    call print_string
    call get_input
    
    ; Convert input to number
    xor rax, rax
    xor rbx, rbx    ; Reset rbx for height
    lea rsi, [rel input_buffer]
.height_loop:
    movzx rdx, byte [rsi]
    cmp rdx, 0          ; Check for null terminator
    je .height_done
    cmp rdx, 10         ; Check for newline
    je .height_done
    cmp rdx, '0'        ; Check if below '0'
    jl .invalid_size
    cmp rdx, '9'        ; Check if above '9'
    jg .invalid_size
    
    sub rdx, '0'
    imul rbx, 10
    add rbx, rdx
    inc rsi
    jmp .height_loop
    
.height_done:
    mov rax, rbx
    cmp rax, min_height
    jl .invalid_size
    cmp rax, max_height
    jg .invalid_size
    
    mov [height], rax
    
    ; Clear and reload default pattern
    call clear_boards
    call load_glider
    jmp .size_done
    
.invalid_size:
    lea rsi, [rel err_size]
    call print_string
    
.size_done:
    ; Clear input buffer before returning
    mov byte [input_buffer], 0
    
    pop rbx     ; Restore rbx
    leave
    ret

; Toggle color mode
toggle_colors:
    push rbp
    mov rbp, rsp
    push rbx            ; Save registers we'll use
    
    ; Toggle the color flag
    xor byte [use_colors], 1
    
    ; Clear input buffer
    mov byte [input_buffer], 0
    
    ; Show current state
    cmp byte [use_colors], 0
    je .colors_off
    
    lea rsi, [rel msg_colors_on]
    jmp .show_msg
    
.colors_off:
    lea rsi, [rel msg_colors_off]
    
.show_msg:
    call print_string
    
    ; Add a small delay to show the message
    mov rax, 35         ; sys_nanosleep
    lea rdi, [rel short_delay]
    xor rsi, rsi
    syscall
    
    ; Clear screen before returning to menu
    call clear_screen
    
    pop rbx             ; Restore registers
    leave
    ret

; Show help screen
show_help:
    push rbp
    mov rbp, rsp
    
    call clear_screen
    
    lea rsi, [rel menu_header]
    call print_string
    lea rsi, [rel controls_info]
    call print_string
    
    ; Wait for any key
    call get_input
    
    ; Don't process the input, just return to menu
    mov byte [input_buffer], 0
    
    leave
    ret

; Add pattern loading functions
load_blinker:
    push rbp
    mov rbp, rsp
    push rbx
    
    ; Clear the board first
    call clear_boards
    
    ; Calculate center position
    mov rax, [height]
    shr rax, 1          ; height/2
    mul qword [width]   ; * width
    mov rbx, [width]
    shr rbx, 1          ; width/2
    add rax, rbx        ; Add column offset
    
    lea rdi, [rel current_gen]
    add rdi, rax        ; rdi now points to center of board
    
    ; Place blinker pattern (horizontal line of 3 cells):
    ; ###
    mov byte [rdi - 1], 1
    mov byte [rdi], 1
    mov byte [rdi + 1], 1
    
    mov byte [current_pattern], 2
    pop rbx
    leave
    ret

load_block:
    push rbp
    mov rbp, rsp
    push rbx
    
    ; Clear the board first
    call clear_boards
    
    ; Calculate center position
    mov rax, [height]
    shr rax, 1          ; height/2
    mul qword [width]   ; * width
    mov rbx, [width]
    shr rbx, 1          ; width/2
    add rax, rbx        ; Add column offset
    
    lea rdi, [rel current_gen]
    add rdi, rax        ; rdi now points to center of board
    
    ; Place block pattern (2x2 square):
    ; ##
    ; ##
    mov byte [rdi], 1
    mov byte [rdi + 1], 1
    add rdi, [width]
    mov byte [rdi], 1
    mov byte [rdi + 1], 1
    
    mov byte [current_pattern], 3
    pop rbx
    leave
    ret

load_beacon:
    push rbp
    mov rbp, rsp
    push rbx
    
    ; Clear the board first
    call clear_boards
    
    ; Calculate center position
    mov rax, [height]
    shr rax, 1          ; height/2
    mul qword [width]   ; * width
    mov rbx, [width]
    shr rbx, 1          ; width/2
    add rax, rbx        ; Add column offset
    
    lea rdi, [rel current_gen]
    add rdi, rax        ; rdi now points to center of board
    
    ; Place beacon pattern (two offset 2x2 blocks):
    ; ##..
    ; ##..
    ; ..##
    ; ..##
    mov byte [rdi], 1
    mov byte [rdi + 1], 1
    add rdi, [width]
    mov byte [rdi + 2], 1
    mov byte [rdi + 3], 1
    add rdi, [width]
    mov byte [rdi + 2], 1
    mov byte [rdi + 3], 1
    
    mov byte [current_pattern], 4
    pop rbx
    leave
    ret

; Signal handler
signal_handler:
    ; Don't push/pop registers - we want to be minimal in signal handler
    
    ; Just exit immediately and safely
    mov rax, 60         ; sys_exit
    xor rdi, rdi        ; status = 0
    syscall
    
    ; Remove the ret instruction - we never return from signal handler
    ; ret   ; <-- Remove this if it exists

; Signal restorer (required for some systems)
signal_restorer:
    mov rax, 15         ; rt_sigreturn
    syscall

; Add error checking for system calls
.check_syscall:
    test rax, rax
    js .handle_error    ; Jump if system call failed
    
.handle_error:
    ; Save error code
    push rax
    
    ; Display error message
    lea rsi, [rel err_syscall]
    call print_string
    
    ; Restore terminal and exit
    call restore_terminal
    
    pop rdi            ; Use error code as exit status
    mov rax, 60        ; sys_exit
    syscall

; Validate board dimensions
validate_size:
    push rbp
    mov rbp, rsp
    
    ; Check width
    cmp qword [width], 10
    jl .invalid_size
    cmp qword [width], max_width
    jg .invalid_size
    
    ; Check height
    cmp qword [height], 10
    jl .invalid_size
    cmp qword [height], max_height
    jg .invalid_size
    
    xor rax, rax    ; Return success
    leave
    ret
    
.invalid_size:
    mov rax, 1      ; Return error
    leave
    ret

; Better terminal cleanup
cleanup_terminal:
    push rbp
    mov rbp, rsp
    
    ; Reset colors
    lea rsi, [rel color_reset]
    call print_string
    
    ; Show cursor
    lea rsi, [rel show_cursor]
    call print_string
    
    ; Return to main screen
    lea rsi, [rel exit_alt_screen]
    call print_string
    
    ; Restore terminal settings
    call restore_terminal
    
    leave
    ret

; Generic pattern loading function
load_pattern:
    ; rdi = pattern index
    push rbp
    mov rbp, rsp
    
    ; Calculate pattern offset
    ; Load pattern dimensions
    ; Copy pattern to board

; New cleanup function
cleanup_game:
    push rbp
    mov rbp, rsp
    
    ; Restore terminal state
    call restore_terminal
    
    ; Clear screen
    call clear_screen
    
    ; Reset all game state
    mov byte [is_paused], 0
    mov byte [input_buffer], 0
    mov qword [gen_count], 0
    
    ; Clear the boards
    call clear_boards
    
    leave
    ret
