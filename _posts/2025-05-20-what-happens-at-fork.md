---
layout: post
title: What happens when you fork()?
date: 2025-05-20T02:52:11+01:00
tags:
---

### Preamble

For a long time I've never understood how `fork()` works. Specifically, I didn't understand what's going on
this piece of code:

```c
#include <stdio.h>
#include <unistd.h>

void gofork(void) {
  int cpid = fork();
  switch (cpid) {
  case -1:
    perror("fork");
    exit(EXIT_FAILURE);
  case 0:
    puts("something for the child");
    break;
  default:
    puts("all hail the mother earth. hail!");
    break;
  }
}
```

My confusion was how come I was seeing the output of the `puts()` calls -- forgetting that `fork()` creates a
clone process. For instance, I wondered why (or how) the other cases except `case -1` both execute instead of
just one of them.

### The details

So what actually happens when `fork()`? Your program is cloned and have some of its properties updated, then
it continues the execution its own version of the calling function. That's it.

> I'm a Linux-based programmer, my explorations are thus targeted to work on Linux-compatible systems.
>
> I think `fork` is called `CreateProcess` in WinAPI

1. The current process is cloned verbatim using the `clone` system call
2. Various process parameters are updated to ensure that the new process (child process) is unique,
   for example:
    - its process ID is set to the lowest available one
    - its parent process ID is set to that forking process's ID
    - its pending signals are cleared
    - its resource usages are set to 0 etc.
       (see here [`fork(2)`](https://man7.org/linux/man-pages/man2/fork.2.html))
3. The child process continue to execute the calling function. In this case, `fork()` return 0 (SUCCESS),
   so `"something for the child"` is printed, the parent gets the returned PID of the child:

    ```c
    #include <stdio.h>
    #include <unistd.h>

    void gofork(void) {
      int cpid = fork();
      switch (cpid) {
      case -1:
        perror("fork");
        exit(EXIT_FAILURE);
      case 0:
        printf("detached pid=%d, ppid=%d, tid=0x%x\n", getpid(), getppid());
        break;
      default:
        printf("cpid=%d [pid=%d] ppid=%d, tid=0x%x\n", cpid, getpid(), getppid());
        break;
      }
    }
    ```
4. The child may be waited upon by the parent with `wait(2)` or `waitpid(2)` for reaping (clean up).

### But what if I don't want the child to inherit "anything" from the parent process?

That is, I want a "clean" address space for the child. The options are `vfork(2)`, `clone(2)`, `clone3(2)`,
or `execve*()`.
  - `vfork(2)`, `clone(2)`, `clone3(2)` are similar (to `fork(2)`) in that they create a new clean process, 
    but accepts at least an pointer to the function to execute in the new process.
    They're more involved to used.

  - `execve*()` family of calls execute an executable binary (a program) with arguments or
    a (text) file starting with a shebang line like `#! /path/to/interpreter/for/the/body/of/text/here`
    via the system's command runner, which is `/bin/sh -c` on *NIX systems


### Uses of fork and examples

If you've ever used any program that runs other programs, there's a fork happening there somewhere.

For a (manufactured) example using `ps` command:
```console
$ ps --forest | wl-copy
  PID TTY      TIME COMMAND
 2761 tty8   136:07 /usr/bin/kitty
 3421 tty8     0:07  \_ /usr/bin/kitten __atexit__
13854 pts/3    0:23  \_ kak /home/saed/.config/kitty/kitty.conf
16901 pts/5    0:01  \_ /usr/bin/nu
17522 pts/5    0:06  |   \_ kitten choose-fonts
17537 pts/5    0:02  |       \_ /usr/bin/kitty +runpy from kittens.choose_fonts.backend import main; main()
17894 pts/4    0:00  \_ /usr/bin/nu
18471 pts/4    0:03      \_ /home/saed/.cargo/bin/hx
  348 pts/18   0:00 nu
 2296 pts/18   0:02  \_ zsh
13927 pts/18   0:00      \_ ps
13928 pts/18   0:00      \_ wl-copy
 9418 pts/18   0:00 wl-copy
```

Program to sum numbers in range 0-9 over UNIX pipes
```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

int main(void) {
  int pipefd[2];
  pid_t cpid;

  if (pipe(pipefd) == -1) {
    perror("pipe");
    exit(EXIT_FAILURE);
  }

  cpid = fork();
  if (cpid == -1) {
    perror("fork");
    exit(EXIT_FAILURE);
  }

  const int numbers[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 0};
  const int isz = sizeof(numbers[0]);
  const int n = sizeof(numbers) / isz;
  if (cpid == 0) {
    // in the child, the write end is unused
    // so close it
    close(pipefd[1]);

    char buf[sizeof(numbers[0])] = {0};
    int sum = 0;
    while (read(pipefd[0], buf, isz) > 0) {
      const int num = *(int *)buf;
      dprintf(STDOUT_FILENO, "[child] received %d\n", num);
      sum += num;
    }

    dprintf(STDOUT_FILENO, "[child] sum = %d\n", sum);

    // we're done close our read end
    close(pipefd[0]);
    exit(EXIT_SUCCESS);

  } else {
    // in the parent, the read end is unused
    // so close it
    close(pipefd[0]);

    for (int i = 0; i < n; i += 1) {
      const char *num = (const char *)&numbers[i];
      printf("[parent] pushing: %d\n", numbers[i]);
      write(pipefd[1], num, isz);
    }

    // done
    close(pipefd[1]); /* Reader will see EOF */
    wait(NULL);       /* Wait for child */
    exit(EXIT_SUCCESS);
  }
}
```

```console
~/blogs/atfork $ cc -o rd rd.c
~/blogs/atfork $ ./rd
[parent] pushing: 1
...
[parent] pushing: 0
[child] received 1
...
[child] received 0
[child] sum = 45
```


Other interesting ideas:
- implement `fork()` with `clone()`, possible if one can examine the states/attributes
  of the current thread for the anything about the program counter or something

> TODO: I want to implement something like `strace()` but I haven't figured out how to
> examine the arguments to each syscall
