/**
 * @file vsync_posix.c
 * @brief VSync POSIX-compatible C library implementation
 *
 * Implements POSIX-like API functions by issuing ECALL syscalls
 * to the VSync hardware RTOS. Syscall numbers match vsync_pkg.sv.
 */

#include "vsync_posix.h"

/* =========================================================================
 * GCC Built-in Functions (required by -nostdlib)
 *
 * GCC may emit calls to memcpy/memset for struct/array initialization
 * even with -fno-builtin. These minimal implementations are needed
 * when linking without libc (-nostdlib).
 * ========================================================================= */

/**
 * @brief Copy memory area
 */
void *memcpy(void *dest, const void *src, size_t n)
{
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;
    while (n--) {
        *d++ = *s++;
    }
    return dest;
}

/**
 * @brief Fill memory with a constant byte
 */
void *memset(void *s, int c, size_t n)
{
    unsigned char *p = (unsigned char *)s;
    while (n--) {
        *p++ = (unsigned char)c;
    }
    return s;
}

/* =========================================================================
 * Thread Management
 * ========================================================================= */

/**
 * @brief Create a new thread
 */
int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start_routine)(void *), void *arg)
{
    return (int)syscall4(SYS_PTHREAD_CREATE,
                         (long)thread,
                         (long)attr,
                         (long)start_routine,
                         (long)arg);
}

/**
 * @brief Terminate the calling thread
 */
void pthread_exit(void *retval)
{
    syscall1(SYS_PTHREAD_EXIT, (long)retval);
    /* Should not return, but loop just in case */
    while (1) {
        __asm__ volatile("wfi");
    }
}

/**
 * @brief Yield the processor to another thread
 */
int pthread_yield(void)
{
    return (int)syscall0(SYS_PTHREAD_YIELD);
}

/**
 * @brief Get the calling thread's ID
 */
pthread_t pthread_self(void)
{
    return (pthread_t)syscall0(SYS_PTHREAD_SELF);
}

/**
 * @brief Wait for a thread to terminate
 */
int pthread_join(pthread_t thread, void **retval)
{
    return (int)syscall2(SYS_PTHREAD_JOIN, (long)thread, (long)retval);
}

/**
 * @brief Detach a thread
 */
int pthread_detach(pthread_t thread)
{
    return (int)syscall1(SYS_PTHREAD_DETACH, (long)thread);
}

/* =========================================================================
 * Mutex Operations
 * ========================================================================= */

/**
 * @brief Initialize a mutex
 */
int pthread_mutex_init(pthread_mutex_t *mutex, const pthread_mutexattr_t *attr)
{
    return (int)syscall2(SYS_MUTEX_INIT, (long)mutex, (long)attr);
}

/**
 * @brief Lock a mutex (blocking)
 */
int pthread_mutex_lock(pthread_mutex_t *mutex)
{
    return (int)syscall1(SYS_MUTEX_LOCK, (long)mutex);
}

/**
 * @brief Try to lock a mutex (non-blocking)
 */
int pthread_mutex_trylock(pthread_mutex_t *mutex)
{
    return (int)syscall1(SYS_MUTEX_TRYLOCK, (long)mutex);
}

/**
 * @brief Unlock a mutex
 */
int pthread_mutex_unlock(pthread_mutex_t *mutex)
{
    return (int)syscall1(SYS_MUTEX_UNLOCK, (long)mutex);
}

/**
 * @brief Destroy a mutex
 */
int pthread_mutex_destroy(pthread_mutex_t *mutex)
{
    return (int)syscall1(SYS_MUTEX_DESTROY, (long)mutex);
}

/* =========================================================================
 * Semaphore Operations
 * ========================================================================= */

/**
 * @brief Initialize a semaphore
 */
int sem_init(sem_t *sem, int pshared, unsigned int value)
{
    return (int)syscall3(SYS_SEM_INIT, (long)sem, (long)pshared, (long)value);
}

/**
 * @brief Wait (decrement) on a semaphore (blocking)
 */
int sem_wait(sem_t *sem)
{
    return (int)syscall1(SYS_SEM_WAIT, (long)sem);
}

/**
 * @brief Try to wait on a semaphore (non-blocking)
 */
int sem_trywait(sem_t *sem)
{
    return (int)syscall1(SYS_SEM_TRYWAIT, (long)sem);
}

/**
 * @brief Post (increment) a semaphore
 */
int sem_post(sem_t *sem)
{
    return (int)syscall1(SYS_SEM_POST, (long)sem);
}

/**
 * @brief Get the value of a semaphore
 */
int sem_getvalue(sem_t *sem, int *sval)
{
    return (int)syscall2(SYS_SEM_GETVALUE, (long)sem, (long)sval);
}

/**
 * @brief Destroy a semaphore
 */
int sem_destroy(sem_t *sem)
{
    return (int)syscall1(SYS_SEM_DESTROY, (long)sem);
}

/* =========================================================================
 * Message Queue Operations
 * ========================================================================= */

/**
 * @brief Open a message queue
 */
mqd_t mq_open(const char *name, int oflag)
{
    return (mqd_t)syscall2(SYS_MQ_OPEN, (long)name, (long)oflag);
}

/**
 * @brief Send a message to a queue
 */
int mq_send(mqd_t mqdes, const char *msg_ptr, size_t msg_len,
            unsigned int msg_prio)
{
    return (int)syscall4(SYS_MQ_SEND,
                         (long)mqdes,
                         (long)msg_ptr,
                         (long)msg_len,
                         (long)msg_prio);
}

/**
 * @brief Receive a message from a queue
 */
int mq_receive(mqd_t mqdes, char *msg_ptr, size_t msg_len,
               unsigned int *msg_prio)
{
    return (int)syscall4(SYS_MQ_RECEIVE,
                         (long)mqdes,
                         (long)msg_ptr,
                         (long)msg_len,
                         (long)msg_prio);
}

/**
 * @brief Close a message queue
 */
int mq_close(mqd_t mqdes)
{
    return (int)syscall1(SYS_MQ_CLOSE, (long)mqdes);
}

/* =========================================================================
 * File I/O Operations
 * ========================================================================= */

/**
 * @brief Open a file/device
 */
int open(int fd_type, int flags)
{
    return (int)syscall2(SYS_OPEN, (long)fd_type, (long)flags);
}

/**
 * @brief Close a file descriptor
 */
int close(int fd)
{
    return (int)syscall1(SYS_CLOSE, (long)fd);
}

/**
 * @brief Read from a file descriptor
 */
int read(int fd, void *buf, size_t count)
{
    return (int)syscall3(SYS_READ, (long)fd, (long)buf, (long)count);
}

/**
 * @brief Write to a file descriptor
 *
 * Sends data byte-by-byte via individual syscalls.
 * The posix_hw_layer write handler uses arg1 directly as peripheral write data
 * (periph_wdata = latched_arg1), so each character value must be passed as arg1.
 * For UART TX, the low 8 bits of arg1 become the transmitted byte.
 */
int write(int fd, const void *buf, size_t count)
{
    const unsigned char *p = (const unsigned char *)buf;
    for (size_t i = 0; i < count; i++) {
        long ret = syscall3(SYS_WRITE, (long)fd, (long)p[i], 1);
        if (ret < 0)
            return (int)ret;
    }
    return (int)count;
}

/**
 * @brief Device I/O control
 */
int ioctl(int fd, unsigned long request, unsigned long arg)
{
    return (int)syscall3(SYS_IOCTL, (long)fd, (long)request, (long)arg);
}

/**
 * @brief Reposition file offset
 */
int lseek(int fd, long offset, int whence)
{
    return (int)syscall3(SYS_LSEEK, (long)fd, (long)offset, (long)whence);
}

/* =========================================================================
 * Timer / Clock Operations
 * ========================================================================= */

/**
 * @brief Get current time
 */
int clock_gettime(clockid_t clk_id, timespec_t *tp)
{
    return (int)syscall2(SYS_CLOCK_GETTIME, (long)clk_id, (long)tp);
}

/**
 * @brief Sleep for a specified duration
 */
int nanosleep(const timespec_t *req, timespec_t *rem)
{
    return (int)syscall2(SYS_NANOSLEEP, (long)req, (long)rem);
}
