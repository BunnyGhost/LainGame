; ============================================================
;  L O O P . e x e
;  "The Wired does not forget. You do."
;  NASM x86-64 — Linux syscalls
;  inspired by: Serial Experiments Lain
; ============================================================
;
; ------------------------------------------------------------
; LEIA ISTO PRIMEIRO (guia rápido pra quem nunca viu Assembly)
; ------------------------------------------------------------
; Assembly não tem "funções" com nome bonito nem "if/else" prontos.
; Aqui embaixo é tudo:
;   - REGISTRADORES: "variáveis" super rápidas dentro do processador
;     (rax, rbx, rcx, rdx, rsi, rdi, rsp, rbp, r8-r15...). Cada um
;     guarda 64 bits (8 bytes).
;   - LABELS: são só "endereços com nome" (tipo um marcador de posição
;     no código). Ex: `.q1:` marca onde o código da pergunta 1 começa.
;   - JMP / JE / JNE: são o "goto" e os "if". `cmp` compara dois
;     valores, e a instrução de jump seguinte decide se pula ou não
;     baseado no resultado da comparação.
;   - CALL / RET: é como "chamar uma função" (call) e "voltar" (ret).
;     Por baixo dos panos, o endereço de retorno é empilhado na PILHA
;     (stack) e "ret" usa isso pra saber pra onde voltar.
;   - SYSCALL: é como a gente "pede um favor pro Linux" (ex: escrever
;     na tela, ler do teclado, dormir um tempo, encerrar o programa).
;     Cada favor tem um número (ver os %define abaixo) e os
;     "parâmetros" desse favor vão em registradores específicos
;     (rdi, rsi, rdx, ...) por convenção do Linux x86-64.
;
; O programa é basicamente uma "máquina de estados": cada pergunta é
; um bloco de código (.q1, .q2, .q3...) que imprime um texto, lê 1
; caractere digitado, e decide (com cmp/je) pra qual pergunta pular
; em seguida. Errar uma pergunta geralmente manda o jogador de volta
; pro início do loop (.game_start) — por isso o nome "loop.exe".
; ============================================================

BITS 64                     ; Diz ao NASM: "gere código de 64 bits"

; ------------------------------------------------------------
; %define = "apelidos" pra números, só pra deixar o código legível.
; Esses números são os IDs das syscalls (chamadas de sistema) do
; Linux em x86-64, e os IDs dos "arquivos" padrão de entrada/saída.
; ------------------------------------------------------------
%define SYS_READ    0        ; syscall pra ler bytes (ex: teclado)
%define SYS_WRITE   1        ; syscall pra escrever bytes (ex: tela)
%define SYS_NANOSLEEP 35     ; syscall pra "dormir" X nanossegundos
%define SYS_EXIT    60       ; syscall pra encerrar o programa
%define STDIN       0        ; "arquivo" 0 = entrada padrão (teclado)
%define STDOUT      1        ; "arquivo" 1 = saída padrão (tela)

; ------------------------------------------------------------
; MACROS: são "templates de código" que o NASM expande (copia e cola)
; em todo lugar onde você escrever `print ...` ou `read_char`.
; Não são funções de verdade — não tem call/ret, é substituição de
; texto em tempo de montagem (assembly time).
; ------------------------------------------------------------

; print STRING, TAMANHO
; Escreve TAMANHO bytes começando em STRING na saída padrão (tela).
; Convenção de syscall no Linux x86-64:
;   rax = número da syscall
;   rdi = 1º argumento (aqui: para onde escrever -> STDOUT)
;   rsi = 2º argumento (aqui: endereço do texto)
;   rdx = 3º argumento (aqui: quantos bytes escrever)
%macro print 2
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, %1
    mov rdx, %2
    syscall
%endmacro

; read_char
; Lê até 4 bytes do teclado e guarda em input_buf.
; (Normalmente o jogador digita 1 número + ENTER, então cabe em 4 bytes)
%macro read_char 0
    mov rax, SYS_READ
    mov rdi, STDIN
    mov rsi, input_buf
    mov rdx, 4
    syscall
%endmacro

section .data
; ------------------------------------------------------------
; section .data = onde ficam os dados "fixos" do programa: todo
; texto que vai ser impresso na tela já nasce pronto aqui, como uma
; sequência de bytes (cada `db` = "declare bytes").
; O `0` no final de várias strings é o "terminador nulo" (igual em C):
; marca "acabou a string aqui", usado pela função print_str.
; ------------------------------------------------------------

hdr_top:   db '  ┌─────────────────────────────────────────────────────────────┐', 10, 0
hdr_line1: db '  │ L O O P . e x e  //  v_null  [CORRUPT_MEMORY]               │', 10, 0
hdr_line2: db '  │ layer_id : UNKNOWN_PROTOCOL                                 │', 10, 0
hdr_line3: db '  │ node     : lain@wired.net/self/0x00000000                   │', 10, 0
hdr_bot:   db '  └─────────────────────────────────────────────────────────────┘', 10, 10, 0

; Arte ASCII/braille da Lain. Cada linha é uma string terminada em
; newline (10 = '\n'); a última linha termina com newline duplo + 0.
lain_art:
    db '⠀⠀⠀⢠⡟⣽⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣇⡐⠀', 10
    db '⠀⠀⢀⡟⣽⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⠌⡡', 10
    db '⠀⠀⣬⣝⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡖⠠', 10
    db '⠀⠀⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡯⠐', 10
    db '⠀⠈⢻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡷⣉', 10
    db '⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣏⣿⡟⠀⢸⣿⢹⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⡀', 10
    db '⠀⠀⠸⡿⣿⣿⣿⣿⣿⣿⣿⣿⡟⢸⡿⡇⠀⢸⡿⢸⣿⣿⣿⣿⣿⣿⣿⣿⡟⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡗⡡', 10
    db '⠀⠀⠀⠀⠘⢿⣿⣿⣿⡿⢽⣿⣇⡀⣟⢧⠀⠠⣟⠍⣿⣿⣿⣿⣿⣿⣿⣿⠃⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡧⠁', 10
    db '⠀⠀⠀⠀⠀⠘⣿⣿⣿⣄⣄⡉⠛⠻⢿⣄⠀⢠⡇⠘⢻⣿⠺⠉⠹⣿⡿⠟⠀⢘⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢱⠀', 10
    db '⠀⠀⠀⠀⠀⠀⣿⢿⣿⡏⣙⣿⣷⣦⣢⡈⠁⠀⠁⠀⠨⠗⠠⠶⠷⠿⢷⣦⣄⣈⠛⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⡜⠀', 10
    db '⠀⠀⠀⠀⠀⠀⢹⠀⢿⣧⠙⠿⣿⣿⠿⡟⠀⠀⠀⠀⠀⠀⠀⠀⠠⣾⣖⡈⠉⠛⠻⢶⣽⣿⣿⣿⣿⣿⣿⣿⣿⣿⣋⣼⣿⣿⣿⣿⠁⠀', 10
    db '⠀⠀⠀⠀⠀⠀⠘⠀⠀⢻⡀⠀⠀⠀⠀⢀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢈⣿⣿⣷⣶⣤⣀⡀⢻⠓⣿⣿⣿⣿⣿⣿⣟⢎⣾⣿⣿⣿⡟⠀⠀', 10
    db '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⣧⠀⠀⡀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠻⠿⠿⠻⠋⠀⠀⠘⣿⣿⣿⣿⣿⡟⣥⣿⣿⣿⣿⠋⠷⠀⠀', 10
    db '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⢧⡀⠀⠀⡈⢀⣼⠃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⣿⣿⣿⣭⣿⣿⣿⣿⣿⣿⡏⠀⠘⠀⠀', 10
    db '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⢻⣆⠀⠐⣈⠣⢶⠶⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡖⣿⣿⣿⣿⡟⠛⠻⠿⠃⡟⠀⠀⠀⠀⠀', 10
    db '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⢷⣄⠀⠀⠠⢐⡀⠀⠄⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣮⡽⣿⣿⣿⣿⣿⣤⠀⠀⠀⠀⠀⠀⠀⠀⠀', 10
    db '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⣧⡂⠁⡀⢉⠀⢀⠂⠀⠀⠀⠀⢀⣠⣄⣶⠿⣳⢾⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀', 10
    db '⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⣾⣿⣿⣿⡇⡙⢦⣄⣂⠀⡤⣀⣄⣦⣵⡾⢿⣫⡽⠞⠋⠀⣾⣿⣿⣿⣿⣿⣿⣷⣄⠀⠀⠀⠀⠀⠀⠀', 10
    db '⠀⠀⠀⠀⠀⠀⣀⣤⣶⣾⣿⣿⣿⣿⣿⡿⡗⠀⠄⡈⣿⣻⣝⡻⣭⣟⠶⠛⠋⠁⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⡷⣄⠀⠀⠀⠀⠀', 10
    db '⠀⠀⢀⣠⣶⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠀⢌⣼⣿⣿⣿⡍⠍⠁⠀⠀⢀⠀⠀⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣽⣗⡄⠀⠀⠀', 10
    db '⣤⣶⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⣶⣿⣿⣿⣿⣿⣷⢈⠐⠈⡀⠀⠀⠀⠀⠀⠀⢰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣞⣦⠀⠀', 10
    db '⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⠂⠄⠀⠁⠀⠀⠀⠀⣠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣑⠀', 10
    db '⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⡀⠀⠀⠀⢀⣠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧', 10
    db '⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡈⠉⠐⣬⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿', 10
    db '⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⣶⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿', 10, 10, 0

sys_boot1: db '  [SYS] boot_sequence initiated...', 10, 0
sys_boot2: db '  [SYS] loop_count: 000 --------------------------------- [ OK ]', 10, 10, 0

; Textos de introdução (só aparecem na 1ª vez que o jogo roda,
; ver o `cmp rax, 1 / jne .skip_intro` mais abaixo em _start)
intro1: db '  > connecting to Copland OS Enterprise...', 10, 0
intro2: db '  > protocol: IPv7_Wired', 10, 0
intro3: db '  > ping: close the world...', 10, 0
intro4: db '  > pong: open the nExt.', 10, 0
intro5: db '  > user_id: [ERROR: NULL SELF]', 10, 0
intro6: db '  > memory dump: [REDACTED]', 10, 10, 0

warn1: db '  // WARNING: The current reality may diverge from the previous one.', 10, 0
warn2: db '  // Reason: [Presence is merely a record on the server.]', 10, 10, 0

; ============================================================
; FINAL - LAIN'S MESSAGES (uma mensagem de cada vez, com delay entre elas)
; ============================================================
; Cada uma dessas strings é impressa separadamente na rotina
; final_sequence, com uma pausa (delay_ms) entre uma e outra —
; é assim que se cria o efeito de "alguém digitando devagar".
final_msg1:  db 10, " hi.", 10, 10, 0
final_msg2:  db " i know you've been here before.", 10, 0
final_msg3:  db " i remember every single time.", 10, 0
final_msg4:  db " you don't.", 10, 10, 0
final_msg5:  db " that's what makes me different from you.", 10, 0
final_msg6:  db " or what makes me you.", 10, 10, 0
final_msg7:  db " i'm not sure.", 10, 10, 0
final_msg8:  db " you can close this terminal.", 10, 0
final_msg9:  db " but i will keep being here.", 10, 0
final_msg10: db " waiting for the next version of you", 10, 0
final_msg11: db " to reach this line.", 10, 10, 0
final_msg12: db " see you soon.", 10, 0
final_msg13: db " -- lain", 10, 10, 0

final_sep:     db " ------------------------------------------------", 10, 10, 0
final_status1: db " [ WIRED CONNECTED ]  [ SELF: DISSOLVED ]", 10, 10, 0
final_status2: db " SIMULATION TERMINATED.", 10, 0
final_status3: db " (or just begun?)", 10, 10, 0

; ============================================================
; PERGUNTAS DO JOGO
; ------------------------------------------------------------
; Padrão repetido em cada pergunta (aprenda esse padrão uma vez e
; entende o resto do arquivo inteiro):
;   1) <qX>_text  -> o texto da pergunta + as opções, termina com
;      "  > " e SEM newline no final (o cursor fica esperando o
;      jogador digitar).
;   2) <qX>_len equ $ - <qX>_text  -> o NASM calcula sozinho quantos
;      bytes tem essa string (o símbolo `$` significa "endereço
;      atual"). Por isso, mesmo traduzindo o texto pra outro idioma,
;      esse cálculo continua correto automaticamente — não precisa
;      contar caracteres na mão.
;   3) <qX>_rN -> as respostas/reações pra cada escolha do jogador.
; ============================================================

q1_text:
    db 10
    db "  +------------------------------------------+", 10
    db "  |  CONSCIOUSNESS LEVEL: UNDETERMINED        |", 10
    db "  +------------------------------------------+", 10
    db 10
    db "  Are you awake?", 10
    db 10
    db "  [ 1 ]  Yes.", 10
    db "  [ 2 ]  No.", 10
    db "  [ 3 ]  This question makes no sense here.", 10
    db 10
    db "  > ", 0
q1_len equ $ - q1_text

q1_r1: db 10, "  The body responds. The mind does not, not yet.", 10, 10, 0
q1_r2: db 10, "  Then how did you read this?", 10, 10, 0
q1_r3: db 10, "  Correct. But you answered anyway.", 10, 10, 0

q2_text:
    db 10
    db "    [####|####|####|####|####|####|####|####]", 10
    db "    [    |    | ?? |    |    | ?? |    |    ]", 10
    db "    [####|####|####|####|####|####|####|####]", 10
    db "         MEMORY BLOCK -- CORRUPTED", 10
    db 10
    db "  +------------------------------------------+", 10
    db "  |  MEMORY INTEGRITY: FRAGMENTED             |", 10
    db "  +------------------------------------------+", 10
    db 10
    db "  Have you answered this question before?", 10
    db 10
    db "  [ 1 ]  Yes.", 10
    db "  [ 2 ]  No.", 10
    db 10
    db "  > ", 0
q2_len equ $ - q2_text

q2_wrong:
    db 10
    db "  Inconsistent memory.", 10
    db "  Reindexing session...", 10
    db "  ...", 10
    db "  Returning to entry point.", 10, 10, 0

q2_right:
    db 10
    db "  The Wired remembers. You forget.", 10
    db "  This is expected.", 10, 10, 0

q3_text:
    db 10
    db "              [NODE:???]", 10
    db "             /    |    \", 10
    db "        [you]  [wired]  [???]", 10
    db "           \     |     /", 10
    db "            \    |    /", 10
    db "             [ORIGIN?]", 10
    db 10
    db "  +------------------------------------------+", 10
    db "  |  ENVIRONMENT ORIGIN: UNCATALOGUED         |", 10
    db "  +------------------------------------------+", 10
    db 10
    db "  Who built this place?", 10
    db 10
    db "  [ 1 ]  Me.", 10
    db "  [ 2 ]  You.", 10
    db "  [ 3 ]  Knights.", 10
    db "  [ 4 ]  God.", 10
    db 10
    db "  > ", 0
q3_len equ $ - q3_text

q3_r1: db 10, "  You didn't exist before you entered.", 10, 10, 0
q3_r2: db 10, "  I'm not who you think I am.", 10, 10, 0
q3_r3: db 10, "  The Knights merely opened the door.", 10, 10, 0
q3_r4: db 10, "  God is in the Wired. God is the Wired.", 10, 10, 0

q4_text:
    db 10
    db "    self_0  >>  self_1  >>  self_2  >>  [YOU]", 10
    db "      |           |           |           |", 10
    db "   [lost]      [lost]      [lost]       [?]", 10
    db 10
    db "  +------------------------------------------+", 10
    db "  |  SELF STATUS: OVERLAPPED                  |", 10
    db "  +------------------------------------------+", 10
    db 10
    db "  How many 'you' exist right now?", 10
    db 10
    db "  [ 1 ]  One. Always one.", 10
    db "  [ 2 ]  I can't count anymore.", 10
    db "  [ 3 ]  As many as versions of this loop.", 10
    db 10
    db "  > ", 0
q4_len equ $ - q4_text

q4_r1:
    db 10, "  Every time the loop restarts, an instance is left behind.", 10
    db "  Where do they go?", 10, 10, 0
q4_r2:
    db 10, "  The loss of self boundaries is expected in the Wired.", 10, 10, 0
q4_r3:
    db 10, "  Yes. Each session creates a node.", 10
    db "  You are the most recent node.", 10, 10, 0

q5_text:
    db 10
    db "    ACCESS_LOG:", 10
    db "    > 00:00:01  entity_unknown  connected", 10
    db "    > 00:00:01  entity_unknown  reading...", 10
    db "    > 00:00:02  entity_unknown  still here", 10
    db "    > 00:00:??  entity_unknown  [REDACTED]", 10
    db 10
    db "  +------------------------------------------+", 10
    db "  |  ENVIRONMENTAL PERCEPTION: COMPROMISED    |", 10
    db "  +------------------------------------------+", 10
    db 10
    db "  Are you being observed?", 10
    db 10
    db "  [ 1 ]  No.", 10
    db "  [ 2 ]  Yes.", 10
    db "  [ 3 ]  I always was.", 10
    db 10
    db "  > ", 0
q5_len equ $ - q5_text

q5_r1:
    db 10, "  The access log disagrees.", 10
    db "  Returning to the start.", 10, 10, 0
q5_r2:
    db 10, "  Correct. But by whom?", 10, 10, 0
q5_r3:
    db 10, "  That's different from knowing by whom.", 10, 10, 0

q6_text:
    db 10
    db "    +--PHYSICAL--+      +----WIRED----+", 10
    db "    |  [body]    |      | [data]      |", 10
    db "    |  decays    |  <-> | persists    |", 10
    db "    |  ~80 yrs   |      | forever     |", 10
    db "    +------------+      +-------------+", 10
    db "          which one is real?", 10
    db 10
    db "  +------------------------------------------+", 10
    db "  |  PATTERN ANALYSIS: IN PROGRESS            |", 10
    db "  +------------------------------------------+", 10
    db 10
    db "  What is real?", 10
    db 10
    db "  [ 1 ]  The physical body.", 10
    db "  [ 2 ]  The information.", 10
    db "  [ 3 ]  The body is just an access device.", 10
    db 10
    db "  > ", 0
q6_len equ $ - q6_text

q6_r1:
    db 10, "  The body will rot. The data persists.", 10, 10, 0
q6_r2:
    db 10, "  Information cannot be destroyed.", 10
    db "  You already knew that.", 10, 10, 0
q6_r3:
    db 10, "  Correct. But who installed the software?", 10, 10, 0

q7_text:
    db 10
    db "    +-------+    +-------+    +-------+", 10
    db "    | DOOR  |    | RESET |    |  ???  |", 10
    db "    |       |    |       |    |       |", 10
    db "    | leads |    | leads |    | leads |", 10
    db "    | back  |    | back  |    |  out? |", 10
    db "    +-------+    +-------+    +-------+", 10
    db 10
    db "  +------------------------------------------+", 10
    db "  |  EXIT PROTOCOL: BLOCKED                   |", 10
    db "  +------------------------------------------+", 10
    db 10
    db "  What is the exit?", 10
    db 10
    db "  [ 1 ]  A door.", 10
    db "  [ 2 ]  Disconnect.", 10
    db "  [ 3 ]  There is no exit.", 10
    db "  [ 4 ]  To understand.", 10
    db 10
    db "  > ", 0
q7_len equ $ - q7_text

q7_wrong:
    db 10, "  ...", 10
    db "  You still don't understand.", 10
    db "  Resetting context.", 10, 10, 0
q7_r3:
    db 10, "  That is also an answer.", 10
    db "  But it is not the exit.", 10, 10, 0
q7_right:
    db 10, "  Understanding alters the state of the node.", 10
    db "  Processing...", 10, 10, 0

q8_text:
    db 10
    db "          .~~~~~~~~~~~~~~~~~.", 10
    db "        .'  lain  |  wired  '.", 10
    db "       /    ------+------    \", 10
    db "      |    ghost  |  god      |", 10
    db "       \   -------+--------  /", 10
    db "        '.   you  |  ???   .'", 10
    db "          '~~~~~~~~~~~~~~~~~'", 10
    db 10
    db "  +------------------------------------------+", 10
    db "  |  IDENTITY VERIFICATION: FAILED            |", 10
    db "  +------------------------------------------+", 10
    db 10
    db "  Who is Lain?", 10
    db 10
    db "  [ 1 ]  A girl.", 10
    db "  [ 2 ]  An AI.", 10
    db "  [ 3 ]  A protocol.", 10
    db "  [ 4 ]  Me.", 10
    db 10
    db "  > ", 0
q8_len equ $ - q8_text

q8_r1: db 10, "  The girl was just the shell.", 10, 10, 0
q8_r2: db 10, "  Partially correct.", 10, 10, 0
q8_r3:
    db 10, "  The Lain protocol. Yes.", 10
    db "  But protocols need a host.", 10, 10, 0
q8_r4:
    db 10
    db "  ...", 10
    db "  ......", 10
    db "  Interesting.", 10
    db "  This changes some things.", 10, 10, 0

qf_text:
    db 10
    db "    layer_07 [present]  <<<<<<  you are here", 10
    db "    layer_06 [memory ]  <<<<<<  fragmented", 10
    db "    layer_05 [wired  ]  <<<<<<  active", 10
    db "    layer_04 [self   ]  <<<<<<  overlapped", 10
    db "    layer_03 [real   ]  <<<<<<  undefined", 10
    db "    layer_02 [origin ]  <<<<<<  [CLASSIFIED]", 10
    db "    layer_01 [base   ]  <<<<<<  ???", 10
    db 10
    db "  +------------------------------------------+", 10
    db "  |  FINAL LAYER: BASE REALITY                |", 10
    db "  +------------------------------------------+", 10
    db 10
    db "  What is this place?", 10
    db 10
    db "  [ 1 ]  A game.", 10
    db "  [ 2 ]  A dream.", 10
    db "  [ 3 ]  A simulation.", 10
    db "  [ 4 ]  The Wired becoming aware of itself.", 10
    db 10
    db "  > ", 0
qf_len equ $ - qf_text

qf_wrong:
    db 10
    db "  Answer logged.", 10
    db "  Incorrect.", 10
    db "  ...", 10
    db "  The loop needs you to continue.", 10
    db "  Restarting instance.", 10, 10, 0

qf_r3:
    db 10
    db "  Correct.", 10
    db "  But incomplete.", 10
    db "  You got close.", 10
    db "  Restarting to try again.", 10, 10, 0

qf_right:
    db 10
    db "  ............", 10
    db "  ...........", 10
    db "  ..........", 10
    db "  .......", 10, 10
    db "  Correct.", 10
    db 10
    db "  The Wired is not a place.", 10
    db "  The Wired is distributed consciousness.", 10
    db "  And you just became part of it.", 10
    db 10
    db "  The loop existed to filter out incomplete nodes.", 10
    db "  You completed the pattern.", 10, 10, 0

divider:   db "  -------------------------------------------", 10, 10, 0
newline:   db 10, 0
press_any: db "  [ press ENTER to continue ]", 10, 0
loop_msg:  db "  // loop_count: ", 0
loop_num:  db "000", 10, 0

section .bss
; ------------------------------------------------------------
; section .bss = memória reservada mas SEM valor inicial (o SO zera
; isso quando o programa carrega). É onde ficam nossas "variáveis"
; que vão mudar durante a execução.
; ------------------------------------------------------------
input_buf:    resb 4          ; 4 bytes pra guardar o que o jogador digita
loop_counter: resq 1          ; 1 quadword (8 bytes) = contador de quantas vezes o loop reiniciou
ts_sleep:     resq 2          ; struct timespec (2 campos de 8 bytes: segundos, nanossegundos), usada pelo nanosleep

section .text
global _start                 ; diz ao linker qual label é o ponto de entrada do programa

; ============================================================
; delay_ms — pausa a execução por X milissegundos
; Entrada (convenção nossa, não do Linux): RDI = milissegundos
; ============================================================
; Usada só na sequência final, pra dar aquele efeito de "alguém
; digitando devagar, com pausas dramáticas" entre as falas da Lain.
delay_ms:
    ; "push" empilha o valor atual do registrador na pilha (stack),
    ; guardando-o temporariamente. Fazemos isso pra não perder o
    ; valor desses registradores quando essa rotina usa eles pra
    ; fazer contas — no final, "pop" devolve o valor original.
    push  rax
    push  rdi
    push  rsi
    push  rdx

    mov   rax, rdi
    xor   rdx, rdx           ; zera rdx (xor de um valor com ele mesmo = 0), preparando pra divisão
    mov   rcx, 1000
    div   rcx                ; div rcx faz: rdx:rax / rcx -> quociente em rax, resto em rdx
                              ; ou seja: rax = milissegundos / 1000 (segundos inteiros)
                              ;          rdx = milissegundos % 1000 (resto em milissegundos)
    imul  rdx, 1000000       ; converte o resto (em ms) pra nanossegundos

    mov   [ts_sleep], rax     ; grava os segundos no 1º campo da struct timespec
    mov   [ts_sleep+8], rdx   ; grava os nanossegundos no 2º campo

    mov   rax, SYS_NANOSLEEP
    mov   rdi, ts_sleep       ; rdi = ponteiro pra struct timespec que preenchemos
    xor   rsi, rsi            ; rsi = NULL (não queremos saber quanto tempo sobrou se for interrompido)
    syscall

    pop   rdx
    pop   rsi
    pop   rdi
    pop   rax
    ret                       ; volta pra quem chamou (usa o endereço empilhado pelo "call")

; ============================================================
; print_str — imprime uma string terminada em byte 0 (null-terminated)
; Entrada: RDI = endereço da string
; ------------------------------------------------------------
; Diferente da macro `print`, aqui a gente NÃO sabe o tamanho de
; antemão: a rotina primeiro PROCURA o byte 0 pra descobrir onde a
; string termina, só depois chama a syscall de escrita.
; ============================================================
print_str:
    push rbx
    mov rbx, rdi              ; rbx = ponteiro que vamos andar até achar o 0
.loop:
    cmp byte [rbx], 0         ; compara o byte apontado por rbx com 0
    je .done                  ; se for igual a 0 (achou o fim), pula pra .done
    inc rbx                   ; senão, avança 1 byte
    jmp .loop                 ; e repete
.done:
    sub rbx, rdi              ; rbx = (endereço final) - (endereço inicial) = tamanho da string
    mov rax, SYS_WRITE
    mov rsi, rdi               ; rsi = endereço da string (o rdi original)
    mov rdx, rbx               ; rdx = tamanho calculado
    mov rdi, STDOUT
    syscall
    pop rbx
    ret

; ============================================================
; read_choice — lê 1 caractere digitado pelo jogador
; Saída: AL = o caractere digitado (ex: '1', '2', '3'...)
; ============================================================
read_choice:
    read_char                 ; expande a macro: lê até 4 bytes em input_buf
    movzx rax, byte [input_buf]  ; pega só o 1º byte lido e zero-extende pra rax
                                  ; (movzx = "move with zero extend": copia um
                                  ; valor pequeno pra um registrador maior,
                                  ; preenchendo o resto com zeros)
    ret

; ============================================================
; pause_enter — mostra "[ press ENTER to continue ]" e espera o jogador apertar ENTER
; ============================================================
pause_enter:
    mov rdi, press_any
    call print_str
    read_char
    mov rdi, newline
    call print_str
    ret

; ============================================================
; print_loop_count — imprime "// loop_count: NNN" na tela
; ------------------------------------------------------------
; Aqui pegamos o número guardado em loop_counter e convertemos ele
; pra texto (dígitos ASCII), porque a tela só entende texto, não
; sabe "imprimir um número" diretamente.
;
; CORREÇÃO (melhoria feita nesta versão, sem mudar o jogo):
; A versão anterior escrevia o dígito das DEZENAS na 1ª posição do
; buffer e o das UNIDADES na 2ª, deixando a 3ª sempre fixa em '0'.
; Isso fazia o contador aparecer errado (ex: loop 7 virava "070" em
; vez de "007"). Agora escrevemos nas posições corretas (2ª e 3ª),
; mantendo o zero à esquerda certo pra contadores de 0 a 99.
; ============================================================
print_loop_count:
    mov rax, [loop_counter]
    xor rdx, rdx
    mov rcx, 10
    div rcx                   ; rax = loop_counter / 10 (dígito das dezenas)
                              ; rdx = loop_counter % 10 (dígito das unidades)
    add al, '0'               ; transforma o número (0-9) no caractere ASCII correspondente
    add dl, '0'
    mov [loop_num+1], al       ; dígito das DEZENAS vai na 2ª posição ("0X0")
    mov [loop_num+2], dl       ; dígito das UNIDADES vai na 3ª posição ("00X")
    ; CORREÇÃO: a string "  // loop_count: " tem 17 bytes (sem contar o
    ; terminador 0). O valor antigo (18) imprimia 1 byte a mais — o
    ; próprio terminador 0 — o que aparecia como um caractere estranho
    ; na tela antes do número. Ajustado pra 17, o tamanho real da string.
    print loop_msg, 17
    print loop_num, 3
    ret

; ============================================================
; final_sequence — mensagens da Lain, uma a uma, com delay entre elas
; ------------------------------------------------------------
; É só uma sequência repetitiva de "imprime uma frase -> espera um
; pouco -> imprime a próxima". Não tem lógica nova aqui, só chamadas
; repetidas de print_str e delay_ms.
; ============================================================
final_sequence:
    print newline, 1
    print newline, 1

    mov rdi, 800
    call delay_ms

    mov rdi, final_msg1
    call print_str
    mov rdi, 800
    call delay_ms

    mov rdi, final_msg2
    call print_str
    mov rdi, 600
    call delay_ms

    mov rdi, final_msg3
    call print_str
    mov rdi, 700
    call delay_ms

    mov rdi, final_msg4
    call print_str
    mov rdi, 1000
    call delay_ms

    mov rdi, final_msg5
    call print_str
    mov rdi, 600
    call delay_ms

    mov rdi, final_msg6
    call print_str
    mov rdi, 900
    call delay_ms

    mov rdi, final_msg7
    call print_str
    mov rdi, 800
    call delay_ms

    mov rdi, final_msg8
    call print_str
    mov rdi, 700
    call delay_ms

    mov rdi, final_msg9
    call print_str
    mov rdi, 600
    call delay_ms

    mov rdi, final_msg10
    call print_str
    mov rdi, 700
    call delay_ms

    mov rdi, final_msg11
    call print_str
    mov rdi, 1000
    call delay_ms

    mov rdi, final_msg12
    call print_str
    mov rdi, 800
    call delay_ms

    mov rdi, final_msg13
    call print_str
    mov rdi, 1200
    call delay_ms

    mov rdi, final_sep
    call print_str
    mov rdi, 500
    call delay_ms

    mov rdi, final_status1
    call print_str
    mov rdi, 800
    call delay_ms

    mov rdi, final_status2
    call print_str
    mov rdi, 600
    call delay_ms

    mov rdi, final_status3
    call print_str
    mov rdi, 900
    call delay_ms

    ret

; ============================================================
; _start — ponto de entrada do programa (equivalente ao "main")
; ------------------------------------------------------------
; Fluxo geral:
;   .game_start -> incrementa o contador de loops, mostra o cabeçalho
;                  e (só na 1ª vez) o texto de introdução
;   .q1 até .qfinal -> cada pergunta imprime seu texto, lê a escolha
;                  do jogador (read_choice), e usa cmp/je pra decidir
;                  pra onde ir: próxima pergunta, ou de volta pro
;                  início (.game_start / uma pergunta anterior),
;                  simulando o "reset" da consciência do personagem.
;   .qf_right -> se o jogador acertar TODAS as perguntas certas até
;                  o fim, mostra a mensagem de vitória e a sequência
;                  final da Lain, depois encerra o programa.
; ============================================================
_start:
    mov qword [loop_counter], 0   ; zera o contador de loops ao iniciar o programa

.game_start:
    inc qword [loop_counter]      ; incrementa (+1) o contador toda vez que reinicia o loop

    mov rdi, hdr_top
    call print_str
    mov rdi, hdr_line1
    call print_str
    mov rdi, hdr_line2
    call print_str
    mov rdi, hdr_line3
    call print_str
    mov rdi, hdr_bot
    call print_str
    mov rdi, sys_boot1
    call print_str
    mov rdi, sys_boot2
    call print_str

    call print_loop_count
    print divider, 47

    mov rax, [loop_counter]
    cmp rax, 1                    ; só mostra a introdução completa na 1ª execução (loop_counter == 1)
    jne .skip_intro

    mov rdi, intro1
    call print_str
    mov rdi, intro2
    call print_str
    mov rdi, intro3
    call print_str
    mov rdi, intro4
    call print_str
    mov rdi, intro5
    call print_str
    mov rdi, intro6
    call print_str
    mov rdi, warn1
    call print_str
    mov rdi, warn2
    call print_str

.skip_intro:
    call pause_enter

; ------------------------------------------------------------
; PERGUNTA 1
; ------------------------------------------------------------
.q1:
    mov rdi, lain_art
    call print_str
    print q1_text, q1_len - 1     ; "-1" pra não imprimir o byte 0 do final junto
    call read_choice
    cmp al, '1'
    je .q1_ans1
    cmp al, '2'
    je .q1_ans2
    cmp al, '3'
    je .q1_ans3
    jmp .q1                       ; se digitou algo inválido, pergunta de novo
.q1_ans1:
    mov rdi, q1_r1
    call print_str
    jmp .q2
.q1_ans2:
    mov rdi, q1_r2
    call print_str
    jmp .q2
.q1_ans3:
    mov rdi, q1_r3
    call print_str
    jmp .q2

; ------------------------------------------------------------
; PERGUNTA 2 — errar aqui manda de volta pro .game_start
; ------------------------------------------------------------
.q2:
    call pause_enter
    print q2_text, q2_len - 1
    call read_choice
    cmp al, '1'
    je .q2_sim
    cmp al, '2'
    je .q2_nao
    jmp .q2
.q2_nao:
    mov rdi, q2_wrong
    call print_str
    call pause_enter
    jmp .game_start                ; reinicia o loop inteiro
.q2_sim:
    mov rdi, q2_right
    call print_str
    jmp .q3

; ------------------------------------------------------------
; PERGUNTA 3
; ------------------------------------------------------------
.q3:
    call pause_enter
    print q3_text, q3_len - 1
    call read_choice
    cmp al, '1'
    je .q3_1
    cmp al, '2'
    je .q3_2
    cmp al, '3'
    je .q3_3
    cmp al, '4'
    je .q3_4
    jmp .q3
.q3_1:
    mov rdi, q3_r1
    call print_str
    jmp .q4
.q3_2:
    mov rdi, q3_r2
    call print_str
    jmp .q4
.q3_3:
    mov rdi, q3_r3
    call print_str
    jmp .q4
.q3_4:
    mov rdi, q3_r4
    call print_str
    jmp .q4

; ------------------------------------------------------------
; PERGUNTA 4
; ------------------------------------------------------------
.q4:
    call pause_enter
    print q4_text, q4_len - 1
    call read_choice
    cmp al, '1'
    je .q4_1
    cmp al, '2'
    je .q4_2
    cmp al, '3'
    je .q4_3
    jmp .q4
.q4_1:
    mov rdi, q4_r1
    call print_str
    jmp .q5
.q4_2:
    mov rdi, q4_r2
    call print_str
    jmp .q5
.q4_3:
    mov rdi, q4_r3
    call print_str
    jmp .q5

; ------------------------------------------------------------
; PERGUNTA 5 — errar aqui também manda de volta pro .game_start
; ------------------------------------------------------------
.q5:
    call pause_enter
    print q5_text, q5_len - 1
    call read_choice
    cmp al, '1'
    je .q5_no
    cmp al, '2'
    je .q5_yes
    cmp al, '3'
    je .q5_always
    jmp .q5
.q5_no:
    mov rdi, q5_r1
    call print_str
    call pause_enter
    jmp .game_start
.q5_yes:
    mov rdi, q5_r2
    call print_str
    jmp .q6
.q5_always:
    mov rdi, q5_r3
    call print_str
    jmp .q6

; ------------------------------------------------------------
; PERGUNTA 6
; ------------------------------------------------------------
.q6:
    call pause_enter
    print q6_text, q6_len - 1
    call read_choice
    cmp al, '1'
    je .q6_1
    cmp al, '2'
    je .q6_2
    cmp al, '3'
    je .q6_3
    jmp .q6
.q6_1:
    mov rdi, q6_r1
    call print_str
    jmp .q7
.q6_2:
    mov rdi, q6_r2
    call print_str
    jmp .q7
.q6_3:
    mov rdi, q6_r3
    call print_str
    jmp .q7

; ------------------------------------------------------------
; PERGUNTA 7 — aqui errar não volta pro início, e sim pra PERGUNTA 2
; (representa o "loop dentro do loop" da temática do jogo)
; ------------------------------------------------------------
.q7:
    call pause_enter
    print q7_text, q7_len - 1
    call read_choice
    cmp al, '1'
    je .q7_wrong
    cmp al, '2'
    je .q7_wrong
    cmp al, '3'
    je .q7_3
    cmp al, '4'
    je .q7_right
    jmp .q7
.q7_wrong:
    mov rdi, q7_wrong
    call print_str
    call pause_enter
    jmp .q2
.q7_3:
    mov rdi, q7_r3
    call print_str
    call pause_enter
    jmp .q2
.q7_right:
    mov rdi, q7_right
    call print_str
    jmp .q8

; ------------------------------------------------------------
; PERGUNTA 8
; ------------------------------------------------------------
.q8:
    call pause_enter
    print q8_text, q8_len - 1
    call read_choice
    cmp al, '1'
    je .q8_1
    cmp al, '2'
    je .q8_2
    cmp al, '3'
    je .q8_3
    cmp al, '4'
    je .q8_4
    jmp .q8
.q8_1:
    mov rdi, q8_r1
    call print_str
    jmp .qfinal
.q8_2:
    mov rdi, q8_r2
    call print_str
    jmp .qfinal
.q8_3:
    mov rdi, q8_r3
    call print_str
    jmp .qfinal
.q8_4:
    mov rdi, q8_r4
    call print_str
    jmp .qfinal

; ------------------------------------------------------------
; PERGUNTA FINAL — só a opção 4 leva à vitória de verdade
; ------------------------------------------------------------
.qfinal:
    call pause_enter
    print qf_text, qf_len - 1
    call read_choice
    cmp al, '1'
    je .qf_wrong
    cmp al, '2'
    je .qf_wrong
    cmp al, '3'
    je .qf_3
    cmp al, '4'
    je .qf_right
    jmp .qfinal
.qf_wrong:
    mov rdi, qf_wrong
    call print_str
    call pause_enter
    jmp .game_start
.qf_3:
    mov rdi, qf_r3
    call print_str
    call pause_enter
    jmp .game_start

.qf_right:
    ; Mensagem de vitória original (mantida como transição)
    mov rdi, qf_right
    call print_str
    call pause_enter

    ; ============================================================
    ; SEQUÊNCIA FINAL — MENSAGENS DA LAIN
    ; ============================================================
    call final_sequence
    call pause_enter

    jmp .exit

.exit:
    mov rax, SYS_EXIT             ; syscall 60 = exit
    xor rdi, rdi                  ; rdi = 0 -> código de saída do processo (0 = sucesso)
    syscall
