# Game of Life

A simulation of Conway's Game of Life implemented in x86-64 assembly. 
This tiny project creates an interactive visualization of cellular automaton following the game rules in your terminal.

If you don't know the rules of the game, you can read about them [here](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life).


### Demo

![Demo](./assets/demo.gif)

## Features

- Interactive visualization in terminal
- Several predefined patterns:
  - Glider
  - Blinker
  - Block
  - Beacon
- Real-time simulation controls:
  - Start/Stop simulation
  - Adjustable simulation speed
  - Grid size customization
  - Colorful and colorless mode
- Cross-platform support through Docker

## Prerequisites

- For native Linux x86-64:
  - NASM assembler
  - GCC compiler
- For other platforms use Docker or Virtualization.

## Installation & Running

### Linux (Native)

Build from source:
```bash
make compile
make run
./gol
```

### Docker (Cross-platform)

```bash
# Build the container
docker build -t game-of-life .

# Run the simulation
docker run -it game-of-life
```

> There are also few Makefile commands to help you with docker env.

## Controls

- `p` - Start/Stop simulation
- `u` - Speed up simulation
- `d` - Slow down simulation
- `Q` - Quit to the menu

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License 

## Acknowledgments

- Conway's Game of Life - [Wikipedia](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life)

---

On MacOS or Windows, you can use things like WSL or Docker to run the project.
Dockerfile is provided in case you want to run it in a container.

