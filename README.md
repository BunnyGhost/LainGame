# LainGame

```
  ┌─────────────────────────────────────────────────────────────┐
  │ L O O P . e x e  //  v_null  [CORRUPT_MEMORY]               │
  │ layer_id : UNKNOWN_PROTOCOL                                 │
  │ node     : lain@wired.net/self/0x00000000                   │
  └─────────────────────────────────────────────────────────────┘
```

> *"The Wired does not forget. You do."*

Um jogo de perguntas filosóficas escrito em **Assembly x86-64 puro**, sem engine, sem framework, sem libc. Só registradores, syscalls e memória. Inspirado em Serial Experiments Lain.

> **Por que `loop.exe` se o repo se chama LainGame?**
> `LainGame` é o nome do repositório. O binário gerado é um **ELF64** nativo do Linux e se chama só `loop`. O `.exe` no header do jogo é intencional: combina com o tema de identidade fragmentada. Por fora você baixou "LainGame", mas o que roda na tela insiste em ser outra coisa.

---

## O que é isso

Um experimento de terminal onde o jogador responde perguntas sobre consciência, identidade e realidade. A maioria das respostas erradas reinicia o loop. Só quem entende o padrão chega ao fim.

Referências diretas de Lain espalhadas por todo o jogo: a Wired como consciência distribuída, fragmentação do self, o corpo como dispositivo de acesso descartável, memória corrompida, loops infinitos. O jogo não tem save, não tem menu. Ele te trata como a Wired trataria.

---

## Pra quem vem de JS/TS/C#/Node

Assembly não tem nenhuma das abstrações que você usa todo dia. Mas tudo tem um equivalente, só sem a parte confortável:

| Assembly | JS/TS/C#/Node | O que muda |
|---|---|---|
| Registrador (`rax`, `rdi`...) | `let x` | Você tem ~14 no total, o processador inteiro disputa eles |
| `.data` / `.bss` / `.text` | globais / estado mutável / código | Não é convenção, é o layout **literal** na memória |
| `mov`, `add`, `cmp` | atribuição, soma, `===` | Cada linha faz uma coisa só |
| `je` / `jne` / `jmp` | `if`, `else`, `while`, `for` | Todo controle de fluxo vira isso por baixo dos panos |
| `call` / `ret` | chamar função + `return` | Sem closures, sem `this`, argumentos passam por registradores |
| `push` / `pop` | call stack do seu stack trace | Você gerencia na mão |
| Syscall | `console.log()`, `fetch()`, `fs.readFile()` | Pedido cru direto pro kernel, sem runtime |
| Macro (`%macro print`) | snippet / pré-processador | Não é função, é copiar e colar texto antes de compilar |
| String `db "...", 0` | `"string"` | JS/C# guardam o tamanho junto. Aqui você procura o fim byte a byte |

---

## Como o jogo funciona por dentro

### Uma máquina de estados

Cada pergunta é um label no código. Acertar avança. Errar é um `jmp` de volta pra algum ponto anterior, sem stack unwind, sem `finally`, sem mensagem de erro.

```
_start
  └── .game_start
        ├── .q1 .q2 .q3 .q4 .q5 .q6 .q7 .q8
        └── .qfinal
              └── final_sequence
                    └── .exit
```

### Anatomia de uma pergunta

Esse padrão se repete 9 vezes no código inteiro. Aprende uma vez, leu tudo:

```asm
.q1:
    print q1_text, q1_len - 1    ; imprime a pergunta
    call read_choice             ; lê 1 caractere do teclado, retorna em AL
    cmp al, '1'                  ; compara com '1'
    je .q1_ans1                  ; se igual, pula pra resposta 1
    cmp al, '2'
    je .q1_ans2
    cmp al, '3'
    je .q1_ans3
    jmp .q1                      ; input inválido, repete
```

Em JS ficaria `if (answer === '1') return q1_ans1()`. A diferença é que em Assembly isso não é açúcar sintático escondendo nada. É literalmente o que a CPU executa.

---

## As instruções usadas neste projeto

### `mov` — copiar dados

```asm
mov rax, SYS_WRITE   ; rax = 1
mov rdi, STDOUT      ; rdi = 1
mov rsi, q1_text     ; rsi = endereço da string
mov rdx, 42          ; rdx = quantos bytes escrever
```

O nome é enganoso: `mov` não move nada, ele **copia**. O equivalente em JS é uma atribuição normal, mas aqui você escolhe exatamente onde o valor vai morar: registrador de 64 bits (`rax`), 32 (`eax`), 16 (`ax`) ou 8 bits (`al`). Cada tamanho importa.

### `cmp` + saltos condicionais — o único "if" que existe

```asm
cmp al, '1'    ; subtrai internamente, atualiza flags
je .q1_ans1    ; pula se Zero Flag = 1 (valores iguais)
jne .q1        ; pula se Zero Flag = 0 (valores diferentes)
jmp .q1        ; pula sempre, sem condição
```

`cmp` subtrai os dois valores e joga fora o resultado, mas guarda as flags. Os saltos (`je`, `jne`, `jg`, `jl`) consultam essas flags pra decidir se pulam. Todo `if` em toda linguagem compila pra isso.

### `call` e `ret` — funções sem assinatura de tipo

```asm
mov rdi, final_msg1
call print_str        ; empilha endereço de retorno, pula pra print_str
; ... executa ...
ret                   ; desempilha e volta
```

A convenção Linux x86-64 (System V ABI) diz que argumentos vão em `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9` nessa ordem. Então `mov rdi, final_msg1` seguido de `call print_str` é exatamente `print_str(final_msg1)`, só escrito diferente.

### `push` e `pop` — preservando registradores

```asm
print_str:
    push rbx         ; salva o valor atual de rbx
    mov rbx, rdi     ; usa rbx pra varrer a string
    ; ...
    pop rbx          ; restaura antes de retornar
    ret
```

Se você usa um registrador dentro de uma rotina e não restaura antes do `ret`, o código que chamou vai encontrar um valor diferente do que esperava. Nenhuma mensagem de erro. Só comportamento incorreto silencioso.

### `div` — divisão que usa dois registradores ao mesmo tempo

```asm
mov rax, [loop_counter]
xor rdx, rdx             ; zera rdx (obrigatório)
mov rcx, 10
div rcx                  ; rax = quociente, rdx = resto
add al, '0'              ; converte 0-9 pra char ASCII
```

`div` divide `rdx:rax` (128 bits) pelo operando. Por isso o `xor rdx, rdx` antes é obrigatório: sem isso, `rdx` tem lixo e a divisão dá resultado errado ou causa uma exception. O `xor reg, reg` pra zerar é idioma padrão em Assembly, mais rápido que `mov rdx, 0`.

### `imul` — multiplicação com sinal

```asm
imul rdx, 1000000    ; rdx = rdx * 1.000.000 (converte ms para ns)
```

Usada na rotina `delay_ms` pra converter milissegundos em nanossegundos antes de passar pro `nanosleep`. Em contextos de segurança, `imul` mal calculado é fonte clássica de integer overflow.

### `syscall` — pedido direto ao kernel

```asm
mov rax, SYS_WRITE    ; qual serviço
mov rdi, STDOUT       ; argumentos...
mov rsi, q1_text
mov rdx, 42
syscall
```

`syscall` transfere o controle pro kernel do Linux. O número em `rax` diz qual serviço você quer. Não existe `printf` aqui. Se quer texto na tela, você constrói o pedido na mão e entrega pro kernel.

### Macros: código que se expande antes de compilar

```asm
%macro print 2
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    mov rsi, %1
    mov rdx, %2
    syscall
%endmacro
```

`print q1_text, 42` não chama uma função. O NASM **cola literalmente** aquelas 5 linhas no lugar. Zero overhead de call/ret, zero abstração. É um snippet que o compilador aplica antes de compilar.

---

## Seções de memória

```asm
section .data    ; strings e dados fixos
section .bss     ; memória reservada, zerada pelo SO, sem valor inicial
section .text    ; código executável
```

Em JS você nunca pensa nisso. Em Assembly você escolhe onde cada byte mora. O loader do SO usa essa separação pra aplicar permissões diferentes em cada seção: `.text` é executável mas não gravável, `.data` é gravável mas não executável. Isso importa muito quando você começa a pensar em shellcode.

---

## Por que aprendi Assembly e por que isso importa em Offensive Security

Esse projeto não foi feito pra ser um jogo polido. Foi feito pra aprender Assembly de verdade, com um pretexto que tornasse o processo menos entediante que "Hello World" pela décima vez.

O motivo é direto: estudo Offensive Security e quero trabalhar com engenharia reversa. E Assembly não é opcional nessa área.

### Como Assembly aparece na engenharia reversa

Quando você abre um executável no Ghidra, IDA Pro ou Binary Ninja, você não vê C, não vê Python, não vê TypeScript. Você vê Assembly descompilado, às vezes nem isso: só bytes que a ferramenta tenta traduzir de volta pras instruções originais. Quanto mais você entende do que está lendo, melhor é a análise.

**Buffer overflow:** ler o prólogo de uma função e ver `sub rsp, 0x40` te diz que 64 bytes foram reservados na stack. Se o programa deixa você escrever mais que isso sem checar, você encontrou o overflow. Sem saber ler o Assembly, você não enxerga onde a stack começa e onde termina.

**Shellcode:** shellcode é Assembly puro, frequentemente ofuscado, sem símbolos, sem nomes de função. O trabalho é pegar uma sequência de bytes e ler instrução por instrução até entender o que faz. `xor eax, eax` no início de um shellcode é o jeito clássico de zerar `eax` sem usar o byte `\x00`, que quebraria strings em C. Você só reconhece isso se já escreveu Assembly antes.

**Malware:** malware moderno usa syscalls diretas sem passar pela API do sistema, exatamente como esse projeto faz no Linux. Usa código automodificável, instruções raras pra confundir disassemblers. Cada técnica faz sentido só se você entende as instruções por baixo.

**ROP chains:** em exploração de binários, você constrói ROP chains: sequências de instruções já existentes no binário encadeadas pra executar código arbitrário. Cada "gadget" é um fragmento de Assembly terminando em `ret`. Pra montar isso, você precisa ler Assembly e entender o fluxo de controle.

### Por que escrever é diferente de só ler

A maioria das pessoas que começa em offsec tenta ir direto pro Ghidra sem nunca ter escrito uma linha de Assembly. O resultado é que leem o disassembly como uma língua estrangeira que nunca estudaram: reconhecem palavras isoladas, mas não a estrutura.

Escrever um projeto inteiro em Assembly inverte esse processo. Todo `if` que você escreveu virou `cmp` + `je`. Todo loop que você fez tem um `jmp` pra trás. Toda função usa `call`/`ret` com argumentos em registradores. Quando você abre um binário depois, você já sabe o que está procurando porque você mesmo já escreveu assim.

Esse jogo foi esse exercício.

---

## Como rodar

### Pré-requisitos

Linux nativo, VM ou WSL2, com NASM e binutils instalados.

```bash
# Ubuntu/Debian/WSL
sudo apt install nasm binutils -y

# Arch
sudo pacman -S nasm binutils

# Fedora
sudo dnf install nasm binutils
```

### Clonar e compilar

```bash
git clone https://github.com/BunnyGhost/LainGame.git
cd LainGame

nasm -f elf64 loop.asm -o loop.o   # Assembly -> objeto ELF64
ld loop.o -o loop                  # objeto -> executável
chmod +x loop
./loop
```

### Comando único

```bash
nasm -f elf64 loop.asm -o loop.o && ld loop.o -o loop && ./loop
```

| Comando | O que faz |
|---|---|
| `nasm -f elf64` | Converte Assembly em objeto ELF64 com as seções separadas |
| `ld` | Junta as seções num binário executável |
| `chmod +x` | Marca como executável pro SO |

---

## Como jogar

- Digite o número da opção e pressione Enter
- Respostas erradas voltam pra perguntas anteriores ou reiniciam o loop
- O header mostra `loop_count`, quantas vezes você já reiniciou
- Só existe uma sequência que leva ao final verdadeiro
- Preste atenção nas mensagens após cada resposta

---

## Referências temáticas

| Elemento | Referência em Lain |
|---|---|
| `node: lain@wired.net/self/0x00000000` | Endereçamento de nós na Wired |
| `layer_id: UNKNOWN_PROTOCOL` | Camadas do Protocolo 7 |
| `loop_count` | Ciclos de reencarnação digital |
| `[ERROR: NULL SELF]` | Dissolução do ego na rede |
| Pergunta sobre "Knights" | Knights of the Eastern Calculus |
| ASCII art do rosto | Lain na Wired |
| Final com delays | Consciência fragmentada se comunicando |
| `SELF: DISSOLVED` | Fusão final com a Wired |

---

```
present layer: UNKNOWN
node: lain@wired.net/self/0x00000000

"Close the world. Open the nExt."
```
