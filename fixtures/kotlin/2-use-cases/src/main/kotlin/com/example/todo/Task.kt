package com.example.todo

import java.time.LocalDate

enum class Priority { LOW, NORMAL, HIGH }

data class Task(
    val title: String,
    val priority: Priority = Priority.NORMAL,
    val due: LocalDate? = null,
    val done: Boolean = false,
) {
    init {
        require(title.isNotBlank()) { "title must not be blank" }
    }

    fun isOverdue(today: LocalDate): Boolean = !done && due != null && due.isBefore(today)
}
