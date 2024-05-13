#!/usr/bin/env wish

# tketris.tcl
# (c) 2024 Rudy Dellomas III <dther+tketris@dther.xyz>
#
# Tketris: A simple Tetris clone in Tcl/Tk 8.6 <=
# The relaxing, if sometimes incredibly unfair, block stacking game.
# Not affiliated with The Tetris Company whatsoever. Name subject to change.
#
# Terminology from the 2009 Tetris Guidelines will be used, but a full
# implementation of said guidelines is not a design goal. However,
# it *is* a design goal to make such an implementation relatively simple,
# should someone wish to do so.
# (If you do, reach out! I'll add an option for it or something.)
#
# This game attempts to implement "classic mode" Tetris. In essence:
# - No bag randomisation (possible to get a hundred S and Z blocks in a row)
# - No complex rotation logic (wall kicks etc.)
# - Simplified "piece locking" logic
# - No "hold" piece
#
# This roughly imitates NES/Gameboy Tetris,
# and is the style of Tetris most people are familiar of.
#
# 2009 TETRIS DESIGN GUIDELINE AVAILABLE HERE:
# https://archive.org/download/2009-tetris-variant-concepts_202201/2009%20Tetris%20Design%20Guideline.pdf

package require Tk
namespace eval Tketris { ;#namespace encapsulates this file

variable game
variable piece
variable matrix
variable widget

proc init {} {
	variable game
	variable piece
	variable widget
	variable matrix

	# constants + settings
	# name: name of app
	# cellsize: visual size of cells in pixels
	# seed: seed given to "expr srand(n)" at new_game
	# skyline: visible space of the buffer, in pixels
	# fallms: milliseconds in between piece "falling" one step
	# basefallms: "fallms" during normal play
	# softdropms: "fallms" when soft dropping (generally basefallms/20)
	# lockms: milliseconds after landing, after which piece is "locked"
	# fallafter: if not false, id given by "after" for the next fall_phase
	# lockafter: like above but for lock_piece
	# locked: if true, player cannot input piece movements
	array set game {
		name Tketris
		cellsize 25
		seed 0
		skyline 10
		fallms 1000
		basefallms 1000
		softdropms 50
		lockms 500
		fallafter false
		lockafter false
		locked true
		nextqueue O
		piece {}
		score 0
		cleared 0
		level 0
	}

	# info on the "board"- a matrix of cells
	# coordinates are relative to the top left fully visible cell,
	# which is x,y:{0 0}.
	# height + width: visible dimensions of game area (0 > x,y > h,w)
	# buffer: height of buffer zone (y < 0)
	# generate: the first area to try generating a new piece (left-center)
	# fallcenter: rotational center of current falling piece
	# fallpiece: cells taken up by the falling piece, relative to center
	array set matrix {
		height 20
		width 10
		buffer 20
		generate {4 -1}
		fallcenter {}
		fallpiece {}
		fallpiecename {}
	}

	# info about pieces
	# rotations are stored as a list of x y pairs, where (0, 0)
	# is the "rotational center".
	# For all pieces except (sometimes) I, this is always an occupied cell.
	# O has no stored rotations, its center is always the bottom-left.
	array set piece [list \
		list {L J I O S Z T}\
		Lcolor orange\
		Jcolor blue\
		Icolor cyan\
		Ocolor yellow\
		Scolor green\
		Zcolor red\
		Tcolor magenta\
		L {}\
		J {}\
		I {}\
		O {0 0  1 0  0 -1  1 -1}\
		S {}\
		Z {}\
		T {}\
	]

	# UI elements
	array set widget {
		matrix .matrix
		previewlabel .previewlabel
		preview .previewlabel.preview
		stats .stats
		score .stats.score
		cleared .stats.cleared
		gamemenu .gamemenu
		newgame .gamemenu.newgame
		options .gamemenu.options
		about .gamemenu.about
	}

	# matrix: game area
	canvas $widget(matrix)\
			-height [expr {
					$matrix(height) * $game(cellsize)
					+ $game(skyline)
				}]\
			-width [expr {
					$matrix(width) * $game(cellsize)
					+ 1
				}]\
			-background grey\
			-takefocus true

	# draw the buffer area just above the play space
	# the player can move pieces around in this area, but if a piece gets
	# locked here, it's game over
	for {set x 0} {$x < $matrix(width)} {incr x} {
		set y -1
		$widget(matrix) create rectangle\
				[expr {$x * $game(cellsize)} + 1]\
				[expr {($y) * $game(cellsize)
					+ $game(skyline)}]\
				[expr {($x + 1) * $game(cellsize)}\
					+ 1]\
				[expr {($y + 1) * $game(cellsize)
					+ $game(skyline)}]\
				-outline "dark grey"\
				-tags {empty buffer cell}
	}

	# initialise grid which will be filled in by pieces during gameplay
	for {set y 0} {$y < $matrix(height)} {incr y} {
		for {set x 0} {$x < $matrix(width)} {incr x} {
			$widget(matrix) create rectangle\
					[expr {$x * $game(cellsize)} + 1]\
					[expr {($y) * $game(cellsize)
						+ $game(skyline)}]\
					[expr {($x + 1) * $game(cellsize)}\
						+ 1]\
					[expr {($y + 1) * $game(cellsize)
						+ $game(skyline)}]\
					-tags {empty matrix cell}
		}
	}

	# piece preview
	ttk::labelframe $widget(previewlabel) -text NEXT
	canvas $widget(preview) \
			-width [expr {$game(cellsize) * 4}]\
			-height [expr {$game(cellsize) * 4}]\
			-background grey
	pack $widget(preview) -padx 2 -pady 2

	# scoreboard (stats)
	ttk::labelframe $widget(stats) -text STATS
	ttk::label $widget(score) -text "Score: 0"
	ttk::label $widget(cleared) -text "Cleared: 0"
	pack $widget(score) -fill x
	pack $widget(cleared) -fill x

	# game menu
	ttk::labelframe $widget(gamemenu) -text MENU
	button $widget(newgame) -text "New Game"\
				-command [namespace code new_game]
	button $widget(options) -text "Options" -command {puts "TODO"}
	button $widget(about) -text "About" -command {puts "TODO"}
	pack $widget(newgame) -fill x
	pack $widget(options) -fill x
	pack $widget(about) -fill x

	# place elements
	grid $widget(matrix) -row 0 -column 0 -rowspan 3 -padx 2 -pady 2
	grid $widget(previewlabel) -row 0 -column 1 -padx 2 -pady 2 -sticky new
	grid $widget(stats) -row 1 -column 1 -padx 2 -pady 2 -sticky new
	grid $widget(gamemenu) -row 2 -column 1 -padx 2 -pady 2 -sticky sew
	grid rowconfigure . 1 -weight 1

	# ensure window is right size
	wm withdraw .
	wm resizable . 0 0
	wm deiconify .

	# virtual events
	event add <<MoveLeft>> <Left> <a>
	event add <<MoveRight>> <Right> <d>
	event add <<HardDrop>> <Up> <w>
	event add <<SoftDropStart>> <Down> <s>
	event add <<SoftDropStop>> <KeyRelease-Down> <KeyRelease-s>
	event add <<RotateRight>> <x> <e>
	event add <<RotateLeft>> <z> <q>
	event add <<Pause>> <Escape>

	bind $widget(matrix) <<MoveLeft>> [namespace code {move_piece left}]
	bind $widget(matrix) <<MoveRight>> [namespace code {move_piece right}]
	bind $widget(matrix) <<SoftDropStart>> [namespace code {soft_drop true}]
	bind $widget(matrix) <<SoftDropStop>> [namespace code {soft_drop false}]
}

# clear matrix, reseed PRNG, restart game
proc new_game {} {
	variable game
	variable widget

	# cancel all timers
	cancel_lock
	cancel_fall

	# seed PRNG
	expr {srand($game(seed))}
	next_piece

	focus $widget(matrix)
	gen_phase
}

# attempt to move piece left or right
proc move_piece {dir} {
	variable game
	variable matrix
	if {$game(locked)} {return}
	set newpos $matrix(fallcenter)
	switch -- $dir {
		left {
			lset newpos 0 [expr [lindex $newpos 0] - 1]
		}
		right {
			lset newpos 0 [expr [lindex $newpos 0] + 1]
		}
	}
	if [valid_move {*}$newpos] {
		set matrix(fallcenter) $newpos
		redraw
		# re-check if we can fall
		if {[can_fall] && $game(fallafter) == false} {
			# XXX Not quite correct behaviour:
			# Tetris guidelines state that the lock should only be
			# paused, and only be cancelled once the piece
			# successfully falls, to prevent stalling forever.
			# Probably doable with [clock milliseconds].
			cancel_lock
			set game(fallafter) [after $game(fallms) [namespace code fall_phase]]
		} elseif {![can_fall] && $game(fallafter) != false} {
			cancel_fall
			lock_phase
		}
	} else {
		bell
		puts "blocked"
	}
}

# start or stop softdrop
proc soft_drop {set} {
	variable game
	if $set {
		set game(fallms) $game(softdropms)
	} else {
		set game(fallms) $game(basefallms)
	}
}

# add new piece to the queue
proc next_piece {} {
	variable game
	variable piece
	# TODO consider making this a queue
	#set rand [expr round(rand() * 7) % 7]
	#set game(nextqueue) [lindex $piece(all) $rand]
	set game(nextqueue) O
}

# convert a matrix coordinate into a coordinate inside $widget(canvas)
# approx. centered on the corresponding visual cell
proc canvas_coord {x y} {
	variable game
	return [list [expr {round($x * $game(cellsize)
				+ ($game(cellsize)/2))}]\
		[expr {round(($y * $game(cellsize))\
				+ ($game(cellsize)/2))\
				+ $game(skyline)}]]
}

# update widget(matrix) based on new game state
proc redraw {} {
	variable game
	variable matrix
	variable widget
	variable piece

	# redraw the falling piece
	if {!$game(locked)} {
		$widget(matrix) itemconfigure falling -fill {}
		tag_piece $widget(matrix) \
			falling $matrix(fallcenter) $matrix(fallpiece)
		$widget(matrix) itemconfigure falling -fill $piece($game(piece)color)
	}
}

# tag the appropriate cells for a given piece
proc tag_piece {canvas tag center piece} {
	variable game
	set cx [lindex $center 0]
	set cy [lindex $center 1]
	$canvas dtag $tag
	foreach {x y} $piece {
		set x [expr ($cx + $x)]
		set y [expr ($cy + $y)]
		$canvas addtag $tag closest {*}[canvas_coord $x $y]
	}
}

# checks if the falling piece can move into the position centered at {x y}
proc valid_move {nx ny} {
	variable matrix
	variable widget

	foreach {px py} $matrix(fallpiece) {
		set x [expr {$nx + $px}]
		set y [expr {$ny + $py}]
		if {$x >= $matrix(width) || $x < 0 || $y >= $matrix(height)} {
			puts "can't move: $x $y out of bounds"
			return false
		}
		# check for filled cells
		if {[cell_occupied $x $y]} {
			puts "can't move: $x $y occupied"
			return false
		}
	}
	return true
}

proc cell_occupied {x y} {
	variable matrix
	variable widget
	variable game

	set cell [$widget(matrix) find closest {*}[canvas_coord $x $y]]
	set tags [$widget(matrix) gettags $cell]
	if {[lsearch -exact -inline $tags full] == {}} {
		return false
	}
	return true
}

proc cancel_fall {} {
	variable game
	if {$game(fallafter) != false} {
		after cancel $game(fallafter)
		set game(fallafter) false
	}
}

proc cancel_lock {} {
	variable game
	if {$game(lockafter) != false} {
		after cancel $game(lockafter)
		set game(lockafter) false
	}
}

proc can_fall {} {
	variable matrix
	set nextfall $matrix(fallcenter)
	lset nextfall 1 [expr [lindex $matrix(fallcenter) 1] + 1]

	return [valid_move {*}$nextfall]
}

# GAME FLOW
# the following functions are called at the beginning of each "phase",
# and repeat until the game is over

# make a new piece 
proc gen_phase {} {
	variable game
	variable matrix
	variable piece

	# ensure these can't happen out of turn
	cancel_fall
	cancel_lock

	puts "generating piece"
	set game(piece) $game(nextqueue)
	next_piece

	# place the center of the piece at $matrix(generate)
	set matrix(fallcenter) $matrix(generate)
	set matrix(fallpiece) $piece($game(piece))

	# if space is available, immediately fall one block down
	# (As stated by the Tetris Guidelines.)
	if {[can_fall]} {
		lset matrix(fallcenter) 1 [expr [lindex $matrix(fallcenter) 1] + 1]
	}

	set game(locked) false
	redraw
	set game(fallafter) [after $game(fallms) [namespace code fall_phase]]
}

# drop the piece one step
# player can begin moving the piece
proc fall_phase {} {
	variable game
	variable matrix

	set matrix(fallcenter) [list [lindex $matrix(fallcenter) 0] [expr [lindex $matrix(fallcenter) 1] + 1]]
	redraw

	if [can_fall] {
		set game(fallafter) [after $game(fallms) [namespace code fall_phase]]
	} else {
		lock_phase
	}
}

# piece has made contact on its bottom side,
# starting the timer for when it is "locked" into place.
proc lock_phase {} {
	variable game

	puts "lock phase start"
	cancel_fall
	set game(lockafter) [after $game(lockms) [namespace code lock_piece]]
}

# player cannot move piece after it has been locked
proc lock_piece {} {
	variable game
	variable matrix
	variable widget

	set game(locked) true
	puts "piece locked at $matrix(fallcenter)"

	$widget(matrix) addtag full withtag falling
	$widget(matrix) dtag falling
	$widget(matrix) dtag full empty

	redraw
	pattern_phase
}

# check for line clears, award points
proc pattern_phase {} {
	clear_phase
}

# update canvas: playing animations, deleting blocks, etc.
# this combines the iterate, animate and eliminate phase.
proc clear_phase {} {
	complete_phase
}

# update stat counters, then return to gen_phase
proc complete_phase {} {
	gen_phase
}

init
} ;# end of namepace eval Tketris
