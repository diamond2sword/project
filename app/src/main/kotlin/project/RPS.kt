package project

object RPS {
	fun main() {
		val hand = Hand.SCISSOR
		val nextHand = Hand.ROCK
		with (Inquirer) {
			receive(hand)
			receive(nextHand)
		}
		println("""
			hand: $hand
			next hand: $nextHand
			winning hand: ${Inquirer.winHand}
		""".trimIndent())
	}

	class Round {
	}
	object Inquirer {
		var hand: Hand? = null
		var winHand: Hand? = null
		fun receive(hand: Hand) {
			winHand= when (hand.winsAgainst(this.hand ?: hand)) {
				true -> hand
				else -> this.hand
			}
			this.hand = hand
		}
	}
	enum class Hand(val value: Int) {
		SCISSOR(0),
		ROCK(1),
		PAPER(2),;
		fun winsAgainst(hand: Hand): Boolean? {
			val x = this.value
			val y = hand.value
			val result = Math.pow((x - y).toDouble(), Math.pow(0.toDouble(), (y - x - 2).toDouble())).toInt()
			return when (result) {
				0 -> null
				else -> result > 0
			}
		}
	}
}
