# Delphi− Scanner

Lexical analyzer for the Delphi− programming language, built with **flex**.

## Environment

| Item | Version / Note |
|------|---------------|
| OS | Ubuntu 24.04 LTS on WSL2 (kernel `6.6.x`) — native Linux 亦可 |
| flex | ≥ 2.6 |
| gcc | ≥ 11 (需支援 C99) |
| make | GNU Make ≥ 4.0 |

### Prerequisites

```bash
sudo apt update && sudo apt install -y flex gcc make
```

## Build

```bash
make
```

## Usage

```bash
./scanner <source_file>
```

Example:

```bash
./scanner HelloWorld.del
```

Reads from **stdin** if no file argument is given:

```bash
echo 'program Test; begin end Test.' | ./scanner
```

## Output Format

Each recognized token is printed on its own line in angle brackets.  
Source lines are echoed with their line number after all tokens on that line have been printed.  
The symbol table (all identifiers) is dumped at the end.

```
<PROGRAM>
<id: HelloWorld>
<';'>
2: program HelloWorld;
...
Symbol Table:
HelloWorld
```

## Clean

```bash
make clean
```
