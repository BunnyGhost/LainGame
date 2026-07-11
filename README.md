# LainGame

```
  ┌─────────────────────────────────────────────────────────────┐
  │ L O O P . e x e  //  v_null  [CORRUPT_MEMORY]               │
  │ layer_id : UNKNOWN_PROTOCOL                                 │
  │ node     : lain@wired.net/self/0x00000000                   │
  └─────────────────────────────────────────────────────────────┘
```

> *"The Wired does not forget. You do."*

Um jogo de perguntas filosóficas escrito inteiramente em **Assembly x86-64 puro** — sem engine, sem framework, sem libc, sem `npm install`. Apenas registradores, syscalls e memória crua. Inspirado no anime **Serial Experiments Lain**.

Se React é uma cidade construída com prédios pré-fabricados, isso aqui é cavar uma caverna com as próprias mãos. Não tem `useState`. Não tem garbage collector. Não tem ninguém te segurando a mão — só você, o processador, e o Linux escutando do outro lado da syscall.

> **Por que o header mostra `loop.exe` se o projeto se chama LainGame?**
> `LainGame` é o nome do repositório — o rótulo que você usa pra encontrar e clonar o projeto. Mas o próprio programa, quando roda, se identifica internamente como `loop.exe` (e nem é um `.exe` de verdade: o binário gerado é um **ELF64**, o formato nativo do Linux — você chama ele só de `loop`). Essa dupla identidade não é acidente de nomenclatura, ela meio que combina com o tema: por fora você sabe que baixou "LainGame", mas o que roda na sua tela insiste em se chamar outra coisa — o mesmo tipo de dissonância entre identidade e rótulo que o jogo pergunta o tempo todo.

---

## 🧠 O que é isso

Um experimento interativo de terminal onde o jogador enfrenta perguntas sobre **consciência, identidade, memória e realidade**. A maioria das respostas erradas reinicia o loop. Só quem entende o padrão chega ao fim — e o próprio código foi desenhado pra ensinar esse padrão te fazendo repeti-lo.

Tematicamente inspirado em Serial Experiments Lain:
- A **Wired** como camada de consciência distribuída
- Fragmentação do **self** em múltiplas instâncias
- O corpo físico como **dispositivo de acesso** descartável
- Memória corrompida, protocolos desconhecidos, loops infinitos
- A pergunta final: *"O que é este lugar?"*

O jogo não tem save, não tem menu, não tem barra de progresso. Ele te trata exatamente como a Wired trataria: você entra, esquece, e tenta de novo.

---

## 🗺️ Para quem vem de JS/TS/C#/Node: um mapa mental rápido

Assembly não tem nenhuma das abstrações que você usa todo dia. Mas quase tudo aqui tem um "primo distante" em linguagens de alto nível — só que sem a parte confortável. Essa tabela é o atalho:

| Em Assembly | Em JS/TS/C#/Node, seria mais ou menos... | A diferença que dói |
|---|---|---|
| Registrador (`rax`, `rdi`...) | Uma variável `let` | Você tem uns 14 no total, e o processador inteiro disputa eles. Não existe "criar mais uma variável" |
| `.data` / `.bss` / `.text` | Separar seu bundle em `const` globais / estado mutável / código | Aqui não é convenção, é o **layout literal na memória** — o SO carrega cada seção num endereço diferente |
| `mov`, `add`, `cmp` | Atribuição, soma, `if (a === b)` | Não existe expressão composta. Cada linha faz **uma coisa** |
| `je` / `jne` / `jmp` | `if`, `else`, `while`, `for` | Todos eles, na real, viram isso por baixo dos panos — até no seu código TypeScript |
| `call` / `ret` | Chamar uma função e dar `return` | Sem closures, sem `this`, sem parâmetros nomeados — os "argumentos" vão em registradores combinados na unha |
| `push` / `pop` (stack) | O call stack que aparece no seu stack trace | Aqui você gerencia essa pilha manualmente quando precisa preservar um valor |
| Syscall (`SYS_WRITE`, `SYS_READ`) | `fetch()`, `fs.writeFile()`, `console.log()` | Não tem runtime, não tem Node por trás. É o pedido **cru** direto pro kernel do Linux |
| Macro (`%macro print`) | Um snippet de VS Code, ou o pré-processador do C | Não é uma função — é **copiar e colar texto** antes mesmo de compilar. Zero overhead, zero abstração |
| String `db "...", 0` | `"minha string"` | JS/C# guardam o tamanho da string junto. Aqui, o "tamanho" é **procurado em runtime**, byte a byte, até achar um `0` |
| Nenhum garbage collector | O GC do V8 / do .NET | Se você não reserva o espaço certo (`resb`, `resq`) e não limpa depois, é problema seu. Pra sempre |

Se você já debugou um `NullReferenceException` em C# ou um `undefined is not a function` em JS, imagina isso **sem stack trace, sem mensagem de erro, só um segfault seco**. É esse o nível de "sem rede de segurança" que a Wired opera.

---

## ⚙️ Como o jogo funciona por dentro

### A metáfora certa: uma máquina de estados, não um "programa"

Esqueça a ideia de "código que roda de cima pra baixo". Pensa nisso como uma **state machine** — tipo um reducer do Redux, só que cada "estado" é um `label` no Assembly e a "transição" é um `jmp`:

```
_start
  └── .game_start        ← incrementa loop_counter, imprime header + ASCII art
        ├── .q1          "Você está acordado?"
        ├── .q2          "Você já respondeu essa pergunta antes?"
        ├── .q3          "Quem construiu este lugar?"
        ├── .q4          "Quantos 'você' existem agora?"
        ├── .q5          "Você está sendo observado?"
        ├── .q6          "O que é real?"
        ├── .q7          "Qual é a saída?"
        ├── .q8          "Quem é Lain?"
        └── .qfinal      "O que é este lugar?"
             └── final_sequence   ← mensagens da Lain com delays
                  └── .exit       ← SYS_EXIT
```

Cada pergunta é um "nó" desse grafo. Errar não é "game over" — é uma **aresta que te leva de volta pra um nó anterior**. Não existe pilha de chamadas te levando pro topo de novo automaticamente: o `jmp .game_start` literalmente teleporta a execução pro início, sem `return`, sem stack unwind, sem `finally`.

### Anatomia de uma pergunta (o padrão que se repete 9 vezes)

Toda pergunta segue exatamente essa receita — aprenda ela uma vez e você já leu o arquivo inteiro:

```asm
.q1:
    print q1_text, q1_len - 1    ; 1) imprime a pergunta na tela
    call read_choice             ; 2) lê 1 caractere do teclado
    cmp al, '1'                  ; 3) compara com a opção 1
    je .q1_ans1                  ;    se for igual, pula pra lá
    cmp al, '2'
    je .q1_ans2
    cmp al, '3'
    je .q1_ans3
    jmp .q1                      ; 4) input inválido → pergunta de novo
```

Se isso fosse escrito em JavaScript, ficaria assim:

```js
function q1() {
  print(q1_text);
  const answer = readChoice();
  if (answer === '1') return q1_ans1();
  if (answer === '2') return q1_ans2();
  if (answer === '3') return q1_ans3();
  return q1(); // input inválido, pergunta de novo
}
```

A diferença é que, em Assembly, esse `if/if/if` não é açúcar sintático escondendo alguma coisa — **é literalmente isso que a CPU faz**, instrução por instrução, sem ninguém traduzindo nada pra você.

### Sem `if`, sem `for`, sem funções de verdade — só isso aqui:

| Instrução | Pra que serve | Analogia |
|---|---|---|
| `cmp a, b` | Compara dois valores e guarda o resultado numa "flag" invisível | O `===` por trás de todo `if` |
| `je` / `jne` | Pula **se** a comparação anterior deu igual / diferente | O corpo de um `if` / `else` |
| `jmp` | Pula sempre, sem condição | Um `goto` puro — o ancestral de todo `while(true)` |
| `call` / `ret` | Guarda o endereço de retorno na pilha e pula; depois volta | `function() {}` + `return`, sem closures |

### O loop e o contador de reincarnações

O jogo guarda quantas vezes você já reiniciou, num pedacinho de memória reservado (não inicializado) na seção `.bss`:

```asm
loop_counter: resq 1    ; reserva 8 bytes (1 quad word) — tipo um "let loopCounter" sem valor inicial
```

- Incrementado toda vez que a execução volta pro `.game_start`
- Mostrado no header como `// loop_count: NNN`
- Na primeira execução (`loop_count == 1`), mostra a introdução completa
- Da segunda em diante, pula direto pro jogo — a Wired não repete a mesma explicação duas vezes pra você, mas também não esquece que você já ouviu

### Delays com nanossegundos (o "typing effect" da Lain)

O final do jogo simula alguém digitando devagar, mensagem por mensagem. Em JS você faria isso com `await new Promise(r => setTimeout(r, ms))`. Aqui, o "await" é uma syscall que efetivamente congela a CPU:

```asm
delay_ms:
    mov   rax, rdi
    div   rcx                 ; rax = segundos, rdx = milissegundos restantes
    imul  rdx, 1000000        ; converte ms → nanossegundos
    mov   [ts_sleep], rax
    mov   [ts_sleep+8], rdx
    mov   rax, SYS_NANOSLEEP
    syscall
```

Sem event loop, sem microtask queue — o processo simplesmente para de existir por um tempinho e o kernel acorda ele depois.

### ASCII art direto na memória

O rosto da Lain (26 linhas de Braille/Unicode) não é "renderizado" em lugar nenhum — ele já nasce pronto, como bytes crus dentro da seção `.data`:

```asm
lain_art:
    db '⠀⠀⠀⢠⡟⣽⣿...', 10
    db '⠀⠀⢀⡟⣽⣿...', 10
    ; ... 24 linhas depois
    db '⣿⣿⣿⣿⣿⣿...', 10, 10, 0
```

`10` é o byte de newline (`\n`) e o `0` final marca "acabou a string" pra função `print_str` — o mesmo princípio de uma string em C, e bem diferente de uma string em JS/C#, que já carrega o próprio tamanho junto.

---

## 🛠️ Stack técnica

| Componente | Tecnologia |
|---|---|
| Linguagem | NASM x86-64 Assembly |
| ABI | Linux syscall direta (sem libc) |
| Arquitetura | x86-64 |
| Syscalls usadas | `write(1)`, `read(0)`, `nanosleep(35)`, `exit(60)` |
| Seções | `.data` (strings), `.bss` (variáveis), `.text` (código) |
| Tema | Serial Experiments Lain |

### Zero dependências externas

O binário final **não linka com libc**. Toda comunicação com o sistema operacional acontece via syscalls Linux diretas — sem `printf`, sem `malloc`, sem `stdio.h`:

```asm
%define SYS_WRITE     1    ; escrever no terminal
%define SYS_READ      0    ; ler input do teclado
%define SYS_NANOSLEEP 35   ; delays precisos entre mensagens
%define SYS_EXIT      60   ; encerrar o processo
```

Isso é o equivalente a, em vez de usar `fetch()`, montar o pacote TCP na mão. Ninguém faz isso em produção — mas fazer isso **uma vez** ensina o que `fetch()` está escondendo de você o tempo todo.

---

## 📚 O que aprendi fazendo isso

### Conceitos de Assembly

- **Syscalls Linux diretas** — como invocar o kernel sem libc, passando argumentos nos registradores certos, na ordem certa
- **Registradores x86-64** — `rax` (número da syscall), `rdi` (1º arg), `rsi` (2º arg), `rdx` (3º arg), `al` (o "byte baixo" de `rax`, usado pra comparar caracteres)
- **Seções de memória** — `.data` (dados já inicializados), `.bss` (memória reservada, zerada pelo SO), `.text` (código executável)
- **Strings null-terminated** — sem tamanho embutido; o fim é marcado por um byte `0`, e alguém precisa procurar por ele
- **Cálculo de tamanho em runtime** — `print_str` varre byte a byte até achar o `0`, pra descobrir quantos bytes escrever

### Controle de fluxo sem abstrações

- Como `if/else` vira `cmp` + `je`/`jne`
- Como loops viram `jmp` de volta pra um label anterior
- Como `switch/case` vira uma sequência de `cmp` + `je`
- Como funções viram `call` + `ret`, com argumentos combinados em registradores por convenção — não por assinatura de tipo

### Por que repetir o mesmo padrão 9 vezes?

**Foi intencional.** Repetir `print → read → cmp → je` em cada pergunta funciona como uma curva de aprendizado embutida no próprio código:

1. **Q1:** você entende o padrão lendo o código
2. **Q2:** já começa a lembrar sem precisar consultar
3. **Q5:** já escreve sem pensar
4. **Q9:** o padrão está gravado — memória muscular, não mais leitura

É a mesma lógica temática do jogo: **o loop existe pra que você entenda o padrão antes de conseguir sair dele.**

### Debugging e ferramentas

- **Montagem:** `nasm -f elf64` gera um objeto ELF64
- **Linkagem:** `ld` junta as seções num binário executável
- **Tamanho do binário:** Assembly puro sem libc fecha em **menos de 20 KB**
- **Erros comuns:** esquecer o `0` no final de uma string, usar o registrador errado numa syscall, não preservar registradores dentro de uma rotina (o equivalente Assembly de mutar uma variável global que outra função não esperava)

---

## 🚀 Como rodar

### Pré-requisitos

- **Linux** (nativo, VM ou WSL2)
- **NASM** (Netwide Assembler)
- **ld** (GNU linker, incluso no binutils)

### Instalação

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install nasm binutils -y

# Arch
sudo pacman -S nasm binutils

# Fedora
sudo dnf install nasm binutils
```

### Baixando o projeto (`git clone`, explicado sem pressupor nada)

Se você nunca mexeu com Git: `git clone` é só o comando que **copia um repositório inteiro do GitHub pro seu computador**. Você cola a URL do repositório, o Git cria uma pasta com o mesmo nome dele, e baixa todos os arquivos ali dentro — é o equivalente a baixar um `.zip` e extrair, só que de um jeito que já vem rastreando o histórico de versões.

O nome depois da última barra na URL (`LainGame`, no caso deste projeto) é o **nome do repositório** — e também vira o nome da pasta criada na sua máquina.

```bash
git clone https://github.com/BunnyGhost/LainGame.git
cd LainGame
```

### Compilar e executar

```bash
nasm -f elf64 loop.asm -o loop.o   # monta Assembly → objeto
ld loop.o -o loop                  # linka objeto → executável
chmod +x loop                      # permissão de execução
./loop                             # roda o jogo
```

### Comando único (build + run)

```bash
nasm -f elf64 loop.asm -o loop.o && ld loop.o -o loop && ./loop
```

### Tamanho do binário final

```bash
$ ls -lh loop
-rwxr-xr-x 1 user user 18K loop
```

18 KB. Sem engine, sem framework, sem runtime — só Assembly. Pra efeito de comparação, um "Hello World" em Electron já passa dos 100 MB.

---

## 🎮 Como jogar

1. **Leia** cada pergunta com atenção
2. **Digite** o número da opção (1, 2, 3 ou 4)
3. **Pressione Enter**
4. Respostas erradas podem:
   - Voltar pra perguntas anteriores
   - Reiniciar o loop inteiro (`jmp .game_start`)
   - Repetir a mesma pergunta até você acertar
5. O header mostra `loop_count` — quantas vezes você já reiniciou
6. **Só existe uma sequência correta** que leva ao final verdadeiro

### Dica

Preste atenção nas **mensagens depois de cada resposta**. Elas carregam pistas sobre o caminho certo. A Wired registra tudo. Você esquece.

---

## 📁 Estrutura do projeto

```
LainGame/
├── loop.asm          # código-fonte completo (~1100 linhas)
├── loop.o            # objeto ELF64 (gerado pelo nasm)
├── loop              # binário executável final
└── README.md         # este arquivo
```

---

## 🎨 Temas e referências

| Elemento do jogo | Referência em Lain |
|---|---|
| `node: lain@wired.net/self/0x00000000` | Endereçamento de nós na Wired |
| `layer_id: UNKNOWN_PROTOCOL` | Camadas de realidade do Protocolo 7 |
| `loop_count` | Ciclos de reencarnação digital |
| `[ERROR: NULL SELF]` | Dissolução do ego na rede |
| `memory dump: [REDACTED]` | Memórias injetadas/removidas |
| Pergunta sobre "Knights" | Os Knights of the Eastern Calculus |
| ASCII art do rosto | Representação visual de Lain na Wired |
| Final com mensagens pausadas | Consciência fragmentada se comunicando |
| `SELF: DISSOLVED` | Fusão final com a Wired |

---

## 🧪 Possíveis extensões

- [ ] Sons via syscall `ioctl` pra beeps do PC speaker
- [ ] Cores ANSI pra destacar camadas e erros
- [ ] Mais finais alternativos baseados em combinações de respostas
- [ ] Easter eggs com comandos especiais (ex: digitar `lain` a qualquer momento)
- [ ] Port pra WASM, pra rodar no navegador
- [ ] Salvar `loop_count` em disco via `open`/`write`, pra persistir entre execuções

---

```
present layer: UNKNOWN
node: lain@wired.net/self/0x00000000

"Close the world. Open the nExt."
```
