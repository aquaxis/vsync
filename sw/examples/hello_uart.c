/**
 * @file hello_uart.c
 * @brief VSync UART Hello World example
 *
 * Simple example demonstrating UART output using the VSync POSIX API.
 * Opens the UART device, writes a greeting message, and closes it.
 */

#include "../lib/vsync_posix.h"

/**
 * @brief Main entry point
 *
 * Opens UART device, writes "Hello VSync!" message, then closes.
 *
 * @return 0 on success, -1 on failure
 */
int main(void)
{
    int fd;

    /* Open UART device */
    fd = open(FD_TYPE_UART, 0);
    if (fd < 0) {
        return -1;
    }

    /* Write greeting message */
    const char msg[] = "Hello VSync!\n";
    write(fd, msg, 14);

    /* Close UART device */
    close(fd);

    return 0;
}
