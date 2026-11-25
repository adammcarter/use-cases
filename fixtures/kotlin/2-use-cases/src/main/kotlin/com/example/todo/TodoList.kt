package com.example.todo

import java.time.LocalDate

class TodoList {
    private val tasks = mutableListOf<Task>()

    fun add(task: Task): TodoList = apply { tasks += task }

    // @use-case:todo.tasks.completion#complete
    fun complete(title: String) {
        val index = tasks.indexOfFirst { it.title == title }
        require(index >= 0) { "no task named '$title'" }
        tasks[index] = tasks[index].copy(done = true)
    }
    // @use-case:end todo.tasks.completion#complete

    fun open(): List<Task> = tasks.filterNot { it.done }

    // @use-case:todo.tasks.agenda#ordering
    /** Overdue first, then by priority (high first), then by due date, undated last. */
    fun agenda(today: LocalDate): List<Task> =
        open().sortedWith(
            compareByDescending<Task> { it.isOverdue(today) }
                .thenByDescending { it.priority }
                .thenBy(nullsLast()) { it.due },
        )
    // @use-case:end todo.tasks.agenda#ordering
}
