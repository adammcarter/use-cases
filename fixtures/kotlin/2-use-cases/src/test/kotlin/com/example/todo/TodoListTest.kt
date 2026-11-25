package com.example.todo

import java.time.LocalDate
import kotlin.test.Ignore
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class TodoListTest {
    private val today = LocalDate.of(2026, 9, 25)

    @Test
    // @use-case:todo.tasks.completion#unit-tests.leaves-open-list
    fun `completed tasks leave the open list`() {
        val list = TodoList().add(Task("write report")).add(Task("book flights"))
        list.complete("write report")
        assertEquals(listOf("book flights"), list.open().map { it.title })
    }
    // @use-case:end todo.tasks.completion#unit-tests.leaves-open-list

    @Test
    // @use-case:todo.tasks.agenda#unit-tests.overdue-first
    fun `agenda puts overdue tasks first`() {
        val list = TodoList()
            .add(Task("renew passport", Priority.LOW, due = today.minusDays(3)))
            .add(Task("ship release", Priority.HIGH, due = today.plusDays(1)))
        assertEquals("renew passport", list.agenda(today).first().title)
    }
    // @use-case:end todo.tasks.agenda#unit-tests.overdue-first

    @Test
    // @use-case:todo.tasks.agenda#unit-tests.priority-then-date
    fun `agenda orders by priority then due date`() {
        val list = TodoList()
            .add(Task("undated high", Priority.HIGH))
            .add(Task("soon high", Priority.HIGH, due = today.plusDays(2)))
            .add(Task("normal", Priority.NORMAL, due = today.plusDays(1)))
        assertEquals(listOf("soon high", "undated high", "normal"), list.agenda(today).map { it.title })
    }
    // @use-case:end todo.tasks.agenda#unit-tests.priority-then-date

    @Test
    // @use-case:todo.tasks.completion#unit-tests.unknown-task
    fun `completing an unknown task fails`() {
        assertFailsWith<IllegalArgumentException> { TodoList().complete("nope") }
    }
    // @use-case:end todo.tasks.completion#unit-tests.unknown-task

    // @use-case:todo.tasks.recurring#unit-tests.reappears
    @Ignore
    @Test
    fun `recurring tasks reappear after completion`() {
        assertTrue(false, "recurrence not implemented")
    }
    // @use-case:end todo.tasks.recurring#unit-tests.reappears
}
