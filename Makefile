.PHONY: build run exec stop

SOURCE_NAME = gol
IMAGE_NAME = asm-gol
CONTAINER_NAME = asm-gol-container

build-docker:
	docker build -t $(IMAGE_NAME) .

run-docker:
	docker run -d \
		--name $(CONTAINER_NAME) \
		-v $(PWD):/app \
		$(IMAGE_NAME)

stop-docker:
	docker rm -f asm-container

exec-docker:
	docker exec -it $(CONTAINER_NAME) /bin/bash

compile:
	nasm -f elf64 $(SOURCE_NAME).asm -o $(SOURCE_NAME).o

link:
	ld -o $(SOURCE_NAME) $(SOURCE_NAME).o
