/**
 * @file multitask.c
 * @brief VSync multitask example with semaphore synchronization
 *
 * Demonstrates multi-threading using the VSync POSIX API.
 * Creates two tasks that synchronize via a semaphore and
 * output messages to UART.
 */

#include "../lib/vsync_posix.h"

/** Global UART file descriptor */
static int uart_fd;

/** Semaphore for task synchronization */
static sem_t sync_sem;

/** Simple string length calculation */
static int strlen_simple(const char *s)
{
    int len = 0;
    while (s[len] != '\0') {
        len++;
    }
    return len;
}

/**
 * @brief Write a null-terminated string to UART
 * @param str String to write
 */
static void uart_puts(const char *str)
{
    write(uart_fd, str, strlen_simple(str));
}

/**
 * @brief Task 1 entry function
 *
 * Waits for semaphore, then outputs a message to UART.
 *
 * @param arg Unused argument
 * @return NULL
 */
static void *task1_func(void *arg)
{
    (void)arg;

    uart_puts("Task1: Waiting for semaphore...\n");

    /* Wait for synchronization signal from Task 2 */
    sem_wait(&sync_sem);

    uart_puts("Task1: Semaphore acquired! Running.\n");

    /* Yield to demonstrate cooperative scheduling */
    pthread_yield();

    uart_puts("Task1: Done.\n");

    return NULL;
}

/**
 * @brief Task 2 entry function
 *
 * Outputs a message to UART, then signals Task 1 via semaphore.
 *
 * @param arg Unused argument
 * @return NULL
 */
static void *task2_func(void *arg)
{
    (void)arg;

    uart_puts("Task2: Starting work...\n");

    /* Simulate some work with a short delay */
    timespec_t delay;
    delay.tv_sec  = 0;
    delay.tv_nsec = 100000000L;  /* 100ms */
    nanosleep(&delay, NULL);

    uart_puts("Task2: Signaling Task1.\n");

    /* Signal Task 1 */
    sem_post(&sync_sem);

    uart_puts("Task2: Done.\n");

    return NULL;
}

/**
 * @brief Main entry point
 *
 * Opens UART, initializes semaphore, creates two tasks,
 * and waits for them to complete.
 *
 * @return 0 on success
 */
int main(void)
{
    pthread_t task1, task2;

    /* Open UART for message output */
    uart_fd = open(FD_TYPE_UART, 0);
    if (uart_fd < 0) {
        return -1;
    }

    uart_puts("Main: VSync Multitask Demo\n");

    /* Initialize semaphore (initial value = 0, for synchronization) */
    sem_init(&sync_sem, 0, 0);

    /* Create Task 1 */
    if (pthread_create(&task1, NULL, task1_func, NULL) != 0) {
        uart_puts("Main: Failed to create Task1\n");
        return -1;
    }

    /* Create Task 2 */
    if (pthread_create(&task2, NULL, task2_func, NULL) != 0) {
        uart_puts("Main: Failed to create Task2\n");
        return -1;
    }

    uart_puts("Main: Tasks created. Waiting for completion.\n");

    /* Wait for both tasks to finish */
    pthread_join(task1, NULL);
    pthread_join(task2, NULL);

    uart_puts("Main: All tasks completed.\n");

    /* Cleanup */
    sem_destroy(&sync_sem);
    close(uart_fd);

    return 0;
}
