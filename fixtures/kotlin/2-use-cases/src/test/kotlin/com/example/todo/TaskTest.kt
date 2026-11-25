package com.example.todo

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TaskTest {
    @Test
    fun blankTitlesAreRejected() {
        assertFailsWith<IllegalArgumentException> { Task("   ") }
    }

    @Test
    // @use-case:todo.tasks.completion#unit-tests.done-not-overdue
    fun doneTasksAreNeverOverdue() {
        val yesterday = LocalDate.of(2026, 9, 24)
        assertTrue(Task("pay bill", due = yesterday).isOverdue(LocalDate.of(2026, 9, 25)))
        assertFalse(Task("pay bill", due = yesterday, done = true).isOverdue(LocalDate.of(2026, 9, 25)))
    }
    // @use-case:end todo.tasks.completion#unit-tests.done-not-overdue
}
