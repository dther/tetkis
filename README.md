# tketris

Tetris clone in Tcl/Tk!

## Notes

Tk is very much built for writing apps rather than games.
This results in a bunch of peculiar behaviours:

### Holding Keys

There's no simple cross-platform way of detecting "key press and hold".
On Linux, at least, once the key starts repeating after being held down,
it begins emitting "KeyPress" and "KeyRelease" in an alternating sequence.

This requires workarounds for actions that should must trigger exactly once.
Currently:

- Soft dropping mostly works, but can act strangely when tapped
- Holding down "Hard Drop" can lead to losing very quickly
- Pieces can be rapidly rotated, slowing down the game

### Interrupting Timers

There's no mechanism for altering an `after` timer after its creation.
It can be cancelled, but one can't, for example,
query and alter the remaining time.

This means a few behaviours aren't quite correct:

- The "lock timer" should only be cleared when a piece reaches a line lower
  than its previous lowest point. (according to the Tetris design doc)
 * At the moment, the lock timer is cleared the moment a piece is
   free to fall. This results in the player being able to stall
   forever by backing in and out of two positions.
- There isn't a robust way to shorten the "fall" timer when soft dropping,
  and instead the code must rely on stopping/restarting the timer

### No Sound

No sound effects or music. Practically the soul of classic Tetris.
Snack has patchy availability at best on modern systems.
(Can't get it to compile right...)

### Dealing with Events

The event queue is both a blessing and a curse.
It's very easy to bind events to occur at exact times,
but passing state between them is incredibly messy.
I'm not entirely clear myself on the delineation between the `game` array
and the `matrix` array, and I wrote them!

All sorts of weird race conditions occur, all the time.

## Reflection

All of this is sort of a shame. I was hoping I'd write more games in pure Tk,
since it's so portable and easy to work with.
Aside from the greebles above, everything works beautifully.

I wonder if I should take up the mantle of writing Tcl bindings for a
cross-platform C game library like Allegro or LOVE2D.
