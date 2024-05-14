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
	# softdropping: "true" when the soft drop button is down.
	# softdropped: set to the value of "softdropping" after a fall,
	#              or immediately after soft dropping (in order to
	#              essentially "speed up" the first soft drop)
	# locked: if true, player cannot input piece movements
	array set game {
		name Tketris
		cellsize 25
		seed 0
		skyline 10
		basefallms 1000
		softdropms 50
		fallms 1000
		lockms 500
		fallafter false
		lockafter false
		softdropping false
		softdropped false
		locked true
		nextqueue {}
		piece {}
		piecefacing {}
		lastaction {}
		score 0
		cleared 0
		level 1
		b2b false
	}

	# info on the "board"- a matrix of cells
	# coordinates are relative to the top left fully visible cell,
	# which is x,y:{0 0}.
	# height + width: visible dimensions of game area (0 > x,y > h,w)
	# buffer: height of buffer zone (y < 0)
	# generate: the first area to try generating a new piece (left-center)
	# fallcenter: rotational center of current falling piece
	# fallpiece: cells taken up by the falling piece, relative to center
	# clearedlines: lines that are full and marked for deletion
	array set matrix {
		height 20
		width 10
		buffer 20
		generate {4 -1}
		fallcenter {}
		fallpiece {}
		clearedlines {}
	}

	# info about pieces
	# rotations are stored as a list of x y pairs, where (0, 0)
	# is the "rotational center".
	# For all pieces except (sometimes) I, this is always an occupied cell.
	# O has no stored rotations, its center is always the bottom-left.
	array set piece [list \
		list {L J I O S Z T}\
		facings {north east south west}\
		Lcolor orange\
		Jcolor blue\
		Icolor cyan\
		Ocolor yellow\
		Scolor green\
		Zcolor red\
		Tcolor magenta\
		O {0 0  1 0  0 -1  1 -1}\
		I {0 -1  -1 -1  1 -1  2 -1}\
		T {0 0  1 0  -1 0  0 -1}\
		L {0 0  1 0  -1 0  1 -1}\
		J {0 0  1 0  -1 0  -1 -1}\
		S {0 0  -1 0  0 -1 1 -1}\
		Z {0 0  1 0  0 -1  -1 -1}\
		eastI {1 0  1 -1  1 -2  1 1}\
		eastT {0 0  0 -1  0 1  1 0}\
		eastL {0 0  0 -1  0 1  1 1}\
		eastJ {0 0  0 -1  0 1  1 -1}\
		eastS {0 0  0 -1  1 0  1 1}\
		eastZ {0 0  0 1  1 0  1 -1}\
		southI {0 0  -1 0  1 0  2 0}\
		southT {0 0  1 0  -1 0  0 1}\
		southL {0 0  1 0  -1 0  -1 1}\
		southJ {0 0  1 0  -1 0  1 1}\
		southS {0 1  -1 1  0 0  1 0}\
		southZ {0 1  1 1  0 0  -1 0}\
		westI {0 0  0 -1  0 -2  0 1}\
		westT {0 0  0 -1  0 1  -1 0}\
		westL {0 0  0 -1  0 1  -1 -1}\
		westJ {0 0  0 -1  0 1  -1 1}\
		westS {-1 0  -1 -1  0 0  0 1}\
		westZ {-1 0  -1 1  0 0  0 -1}\
	]

	# UI elements
	array set widget {
		matrix .matrix
		previewlabel .previewlabel
		preview .previewlabel.preview
		stats .stats
		score .stats.score
		cleared .stats.cleared
		level .stats.level
		lastaction .stats.lastaction
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
	# preview is a 4x4 grid
	for {set y 0} {$y < 4} {incr y} {
		for {set x 0} {$x < 4} {incr x} {
			$widget(preview) create rectangle\
					[expr {$x * $game(cellsize) + 1}]\
					[expr {$y * $game(cellsize) + 1}]\
					[expr {($x + 1) * $game(cellsize) + 1}]\
					[expr {($y + 1) * $game(cellsize) + 1}]\
					-tags {empty cell}
		}
	}
	pack $widget(preview) -padx 2 -pady 2

	# scoreboard (stats)
	ttk::labelframe $widget(stats) -text STATS
	ttk::label $widget(score) -text "Score: 0"
	ttk::label $widget(cleared) -text "Cleared: 0"
	ttk::label $widget(lastaction) -text {} \
				-wraplength [expr {4*$game(cellsize)}]
	ttk::label $widget(level) -text "Level: 0"
	pack $widget(score) -fill x
	pack $widget(cleared) -fill x
	pack $widget(level) -fill x
	pack $widget(lastaction) -fill x

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
	wm title . $game(name)
	wm withdraw .
	wm resizable . 0 0
	wm deiconify .

	# virtual events
	event add <<MoveLeft>> <Left> <a>
	event add <<MoveRight>> <Right> <d>
	event add <<HardDrop>> <Up> <w>
	event add <<SoftDropPress>> <Down> <s>
	event add <<SoftDropRelease>> <KeyRelease-Down> <KeyRelease-s>
	event add <<RotateRight>> <x> <e>
	event add <<RotateLeft>> <z> <q>
	event add <<Pause>> <Escape>

	bind $widget(matrix) <<MoveLeft>> [namespace code {move_piece left}]
	bind $widget(matrix) <<MoveRight>> [namespace code {move_piece right}]
	bind $widget(matrix) <<RotateRight>> [namespace code {rotate_piece right}]
	bind $widget(matrix) <<RotateLeft>> [namespace code {rotate_piece left}]
	bind $widget(matrix) <<SoftDropPress>> [namespace code {soft_drop true}]
	bind $widget(matrix) <<SoftDropRelease>> [namespace code {soft_drop false}]
	bind $widget(matrix) <<HardDrop>> [namespace code {hard_drop}]
}

# clear matrix, reseed PRNG, restart game
proc new_game {} {
	variable game
	variable widget
	variable matrix

	# cancel all timers
	cancel_lock
	cancel_fall

	# reset game and matrix
	array set game {
		skyline 10
		basefallms 1000
		softdropms 50
		fallms 1000
		lockms 500
		fallafter false
		lockafter false
		softdropping false
		softdropped false
		locked true
		nextqueue {}
		piece {}
		piecefacing {}
		lastaction {}
		score 0
		cleared 0
		level 1
		b2b false
	}

	array set matrix {
		fallcenter {}
		fallpiece {}
		clearedlines {}
	}

	# reset all cells
	# ... really used a lot of tags here...
	$widget(matrix) addtag empty withtag cell
	$widget(matrix) dtag cell falling
	$widget(matrix) dtag cell full
	$widget(matrix) dtag cell cleared
	$widget(matrix) dtag cell checked
	$widget(matrix) dtag cell moveup
	$widget(matrix) dtag cell movedown
	$widget(matrix) itemconfigure cell -fill {}
	update_stats
	update idletasks

	# seed PRNG
	expr {srand($game(seed))}
	next_piece

	focus $widget(matrix)
	gen_phase
}

# award points according to the Tetris scoring table
proc award_points {action {tspin false}} {
	variable game
	# TODO T-spins
	switch -- $action {
		1 {set base 100 ; set actionstr "Single"}
		2 {set base 300 ; set actionstr "Double"}
		3 {set base 400 ; set actionstr "Triple"}
		4 {set base 800 ; set actionstr "Tetris"}
		softdrop {
			incr game(score) 1
			update_stats
			return
		}
		harddrop {
			incr game(score) 2
			update_stats
			return
		}
	}

	set total [expr {$base * $game(level)}]
	set actionstr "$actionstr\n($base x $game(level)"
	if {$game(b2b)} {
		set b2bbonus [expr {$total/2}]
		set actionstr "Back-to-Back $actionstr + $b2bbonus"
	} else {
		set b2bbonus 0
	}
	incr total $b2bbonus
	incr game(score) $total
	set actionstr "$actionstr = $total)"
	set game(lastaction) $actionstr
}

# update stat widgets
proc update_stats {} {
	variable widget
	variable game
	$widget(score) configure -text "Score: $game(score)"
	$widget(cleared) configure -text "Cleared: $game(cleared)"
	$widget(level) configure -text "Level: $game(level)"
	$widget(lastaction) configure -text $game(lastaction)
}

# attempt to rotate a piece left (counter clockwise) or right (clockwise)
proc rotate_piece {dir} {
	variable game
	variable piece
	variable matrix

	if {$game(locked) || $game(piece) == "O"} {return}

	# basically treat pieces(facing) like an enum...
	switch -- $game(piecefacing) {
		north {set newfacing 0}
		east {set newfacing 1}
		south {set newfacing 2}
		west {set newfacing 3}
	}
	switch -- $dir {
		left {incr newfacing -1}
		right {incr newfacing 1}
	}
	set newfacing [lindex $piece(facings) [expr {$newfacing % 4}]]

	if {$newfacing == "north"} {
		# pieces start facing north
		set newpiece $piece($game(piece))
	} else {
		set newpiece $piece($newfacing$game(piece))
	}

	if {[valid_move {*}$matrix(fallcenter) $newpiece]} {
		set game(piecefacing) $newfacing
		set matrix(fallpiece) $newpiece
		redraw
	}

	# XXX wall kicks go here
	# if a T piece manages to rotate to a valid position after five tries,
	# and locks as a result, then it's a full (not mini) t-spin

	# check if rotation has caused piece to "lift"
	# (and therefore may cause it to go from locking to falling)
	if {[can_fall] && $game(lockafter) != "false" && $game(fallafter) == false} {
		cancel_lock
		set game(fallafter) [after $game(fallms) [namespace code fall_phase]]
	}
	# TODO: if a T piece successfully rotates and can't fall,
	# set a flag to check for t-spins during lock_piece
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
	}
}

# start or stop softdrop
proc soft_drop {set} {
	variable game
	if $set {
		set game(softdropping) true
		set game(fallms) $game(softdropms)
		if {!$game(softdropped) && [can_fall]} {
			set game(softdropped) true
			cancel_fall
			set game(fallafter) [after $game(fallms) [namespace code fall_phase]]
		}
	} else {
		set game(softdropping) false
		set game(fallms) $game(basefallms)
		if {[can_fall] && $game(fallafter) == false} {
			set game(fallafter) [after $game(fallms) [namespace code fall_phase]]
		}
	}
}

# drop and lock piece immediately
proc hard_drop {} {
	variable matrix
	variable game

	if {$game(locked)} {return}
	cancel_fall
	cancel_lock
	while {[can_fall]} {
		lset matrix(fallcenter) 1 [expr [lindex $matrix(fallcenter) 1] + 1]
		award_points harddrop
		redraw
	}
	lock_piece
}

# add new piece to the queue
proc next_piece {} {
	variable game
	variable piece
	variable widget

	# TODO consider making this a queue
	set rand [expr round(rand() * 7) % 7]
	set game(nextqueue) [lindex $piece(list) $rand]

	# draw preview
	$widget(preview) itemconfigure preview -fill {}
	tag_piece $widget(preview) preview {1 2 preview} $piece($game(nextqueue))
	$widget(preview) itemconfigure preview -fill $piece($game(nextqueue)color)
}

# convert a matrix coordinate into a coordinate inside $widget(canvas)
# approx. centered on the corresponding visual cell
proc canvas_coord {x y {canvas .matrix}} {
	variable game
	variable widget
	if {$canvas != $widget(matrix)} {
		# so that this can be reused for the preview. a bit of a hack
		return [list [expr {round($x * $game(cellsize)
					+ ($game(cellsize)/2))}]\
			[expr {round(($y * $game(cellsize))\
					+ ($game(cellsize)/2))}]]
	}
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
		$canvas addtag $tag closest {*}[canvas_coord $x $y $canvas]
	}
}

# checks if the given piece can move into the position centered at {x y}
# defaults to the current falling piece
proc valid_move {nx ny {piece {}}} {
	variable matrix
	variable widget

	if {$piece == {}} {
		set piece $matrix(fallpiece)
	}
	foreach {px py} $piece {
		set x [expr {$nx + $px}]
		set y [expr {$ny + $py}]
		if {$x >= $matrix(width) || $x < 0 || $y >= $matrix(height)} {
			return false
		}
		# check for filled cells
		if {[cell_occupied $x $y]} {
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

# true if the falling piece has spawned inside an existing piece
proc block_out {} {
	variable matrix
	return [expr {![valid_move {*}$matrix(fallcenter)]}]
}

# true if the last piece locked entirely inside the buffer zone
proc lock_out {} {
	variable matrix
	set cx [lindex $matrix(fallcenter) 0]
	set cy [lindex $matrix(fallcenter) 1]
	foreach {x y} $matrix(fallpiece) {
		incr x $cx
		incr y $cy
		if {$y >= 0} {
			return false
		}
	}
	return true
}

# Game over, man!
proc game_over {} {
	variable game
	variable widget
	cancel_fall
	cancel_lock
	set game(locked) true
	set game(lastaction) "GAME OVER"
	$widget(matrix) itemconfigure empty -fill "red4"
	update_stats
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

	set game(piece) $game(nextqueue)
	set game(piecefacing) north
	next_piece

	# place the center of the piece at $matrix(generate)
	set matrix(fallcenter) $matrix(generate)
	set matrix(fallpiece) $piece($game(piece))
	# start lower for I because its rotational center is higher than others
	if {$game(piece) == "I"} {
		lset matrix(fallcenter) 1 [expr [lindex $matrix(fallcenter) 1] + 1]
	}

	redraw
	if {[block_out]} {
		tailcall game_over
	}

	# if space is available, immediately fall one block down
	# (As stated by the Tetris Guidelines.)
	if {[can_fall]} {
		lset matrix(fallcenter) 1 [expr [lindex $matrix(fallcenter) 1] + 1]
	}

	set game(locked) false
	redraw
	if {[can_fall]} {
		set game(fallafter) [after $game(fallms) [namespace code fall_phase]]
	} else {
		lock_phase
	}
}

# drop the piece one step
# player can begin moving the piece
proc fall_phase {} {
	variable game
	variable matrix

	# one last check before falling,
	# in case an input occurs in between fall_phase that prevents falling
	if {![can_fall]} {
		tailcall lock_phase
	}

	set game(softdropped) $game(softdropping)
	if {$game(softdropped)} {
		award_points softdrop
	}
	set matrix(fallcenter) [list [lindex $matrix(fallcenter) 0] [expr [lindex $matrix(fallcenter) 1] + 1]]
	redraw

	if {[can_fall]} {
		set game(fallafter) [after $game(fallms) [namespace code fall_phase]]
	} else {
		tailcall lock_phase
	}
}

# piece has made contact on its bottom side,
# starting the timer for when it is "locked" into place.
proc lock_phase {} {
	variable game

	cancel_fall
	set game(lockafter) [after $game(lockms) [namespace code lock_piece]]
}

# player cannot move piece after it has been locked
proc lock_piece {} {
	variable game
	variable matrix
	variable widget

	set game(locked) true

	set game(softdropped) false

	$widget(matrix) addtag full withtag falling
	$widget(matrix) dtag falling
	$widget(matrix) dtag full empty

	redraw
	# if the falling piece landed entirely inside buffer zone, game over
	if {[lock_out]} {
		tailcall game_over
	}
	# TODO check for t-spins

	# XXX in multiplayer, this is when incoming attack lines would appear.
	pattern_phase
}

# check for line clears, award points
proc pattern_phase {} {
	variable matrix
	variable widget
	variable game

	cancel_fall
	cancel_lock

	set checklines {}
	foreach {x y} $matrix(fallpiece) {
		set line [expr $y + [lindex $matrix(fallcenter) 1]]
		if {[lsearch -exact -inline $checklines $line] == {}} {
			lappend checklines [expr $line]
		}
	}

	set matrix(clearedlines) {}
	foreach line $checklines {
		set cells [$widget(matrix) find\
				overlapping {*}[canvas_coord 0 $line]\
					{*}[canvas_coord $matrix(width) $line]]
		set clear true
		foreach cell $cells {
			$widget(matrix) addtag checked withtag $cell
			set tags [$widget(matrix) gettags $cell]
			if {[lsearch -exact -inline $tags empty] != {}} {
				set clear false
				break
			}
		}
		if {$clear} {
			lappend matrix(clearedlines) $line
			$widget(matrix) addtag cleared withtag checked
		}
		$widget(matrix) dtag checked
	}

	set linescleared [llength $matrix(clearedlines)] 
	# track back-to-backs
	if {$linescleared == 4} {
		set game(b2b) true
	} elseif {$linescleared > 0} {
		# single, double or triple w/o t-spin ends a back-to-back
		set game(b2b) false
	}

	# award points based on number of lines cleared
	# TODO check for t-spins
	if {$linescleared > 0} {
		incr game(cleared) $linescleared
		award_points $linescleared
	}

	clear_phase
}

# update canvas: playing animations, deleting blocks, etc.
# this combines the iterate, animate and eliminate phase.
proc clear_phase {} {
	variable matrix
	variable widget

	# XXX Iterate would occur here, and is unused.

	# Animate
	set matrix(clearedlines) [lsort -integer $matrix(clearedlines)]
	$widget(matrix) itemconfigure cleared -fill white
	foreach cleared $matrix(clearedlines) {
		shift_line $cleared
	}
	update idletasks
	$widget(matrix) itemconfigure cleared -fill {}
	$widget(matrix) addtag empty withtag cleared
	$widget(matrix) dtag cleared full
	$widget(matrix) dtag cleared

	# Eliminate
	# TODO award points/levels based on $matrix(clearedlines)
	set matrix(clearedlines) {}

	complete_phase
}

# move a cleared line to the top, and the lines above it down
proc shift_line {line} {
	variable matrix
	variable game
	variable widget

	set above [expr {$line - 1}]
	if {$above > 0} {
		$widget(matrix) addtag movedown overlapping {*}[canvas_coord 0 0]\
					{*}[canvas_coord $matrix(width) $above]
	}

	$widget(matrix) addtag moveup overlapping {*}[canvas_coord 0 $line]\
					{*}[canvas_coord $matrix(width) $line]

	# pshhh boring
	#$widget(matrix) move movedown 0 $game(cellsize)
	$widget(matrix) move moveup 0 [expr $game(cellsize) * -1 * $line]

	# XXX animated for style points
	for {set i 0} {$i < $game(cellsize)} {incr i} {
		$widget(matrix) move movedown 0 1
		after 1
		update idletasks
	}

	$widget(matrix) dtag moveup full

	$widget(matrix) dtag moveup
	$widget(matrix) dtag movedown
}

# update stat counters, then return to gen_phase
proc complete_phase {} {
	update_stats
	gen_phase
}

init
} ;# end of namepace eval Tketris
