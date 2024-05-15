#!/usr/bin/env wish

# tketris.tcl
# (c) 2024 Rudy Dellomas III <dther+tketris@dther.xyz>
#
# Tketris: A simple Tetris clone for Tcl/Tk 8.6 <=
# Not affiliated with The Tetris Company whatsoever. Name subject to change.
#
# TODO apply a software license
#
# Feature implementation is guided by the 2009 Tetris Guidelines,
# but occasionally departs from it for reasons of pragmatism.
#
# I hope to implement game modes for both "Classic" Tetris (NES/Gameboy style)
# as well as modern SRS-style Tetris, as well as provide room to implement
# non-official game extensions found in popular fan made Tetris clones,
# such as TETR.IO or Jstris.
# Please reach out if you'd like to lend a hand!
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

	# TODO separate options from game state
	# constants + settings
	# name: name of app
	# cellsize: visual size of cells in pixels
	# seed: seed given to "expr srand(n)" at new_game
	# skyline: visible space of the buffer, in pixels
	# fallms: milliseconds in between piece "falling" one step
	# startfallms: fallms at level 1
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
		animate true
		cellsize 25
		seed -1
		skyline 10
		startfallms 1000
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
		levelcap 15
		goal 10
		b2b false
	}

	# info on the "board"- a matrix of cells
	# coordinates are relative to the bottom left cell,
	# which is x,y:{0 0}.
	# HEIGHT: total height including buffer zone
	# WIDTH: width of play field
	# BUFFER: first row in the buffer
	# GENERATE: the first area to try generating a new piece (left-center)
	# fallcenter: rotational center of current falling piece
	# fallpiece: cells taken up by the falling piece, relative to center
	# clearedlines: lines that are full and marked for deletion
	array set matrix {
		HEIGHT 40
		WIDTH 10
		BUFFER 20
		GENERATE {4 20}
		fallcenter {}
		fallpiece {}
		clearedlines {}
	}

	# info about pieces
	# Modern Tetris uses a lot of hidden calculation to ensure that
	# pieces rotate intuitively.
	# See "rotate_piece" and "get_piece_kicks" for more information.
	#
	# rotations are stored as a list of x y pairs, where (0, 0)
	# is the "rotational center". this is always an occupied cell.
	# The "offset" tables are used to ensure pieces rotate in an
	# intuitive manner, accounting for both "visual center" and "kicks".
	# All pieces except I and O have the same offset table.
	# I is a special case, and has its own offset table.
	# O has no stored rotations and no offsets. It cannot rotate.

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
		O {0 0  1 0  0 1  1 1}\
		I {0 0 -1 0  1 0  2 0}\
		T {0 0  1 0 -1 0  0 1}\
		L {0 0  1 0 -1 0  1 1}\
		J {0 0  1 0 -1 0 -1 1}\
		S {0 0 -1 0  0 1  1 1}\
		Z {0 0  1 0  0 1 -1 1}\
		eastI {0 0  0  1  0 -1  0 -2}\
		eastT {0 0  0  1  0 -1  1  0}\
		eastL {0 0  0  1  0 -1  1 -1}\
		eastJ {0 0  0  1  0 -1  1  1}\
		eastS {0 0  0  1  1  0  1 -1}\
		eastZ {0 0  0 -1  1  0  1  1}\
		southI {0 0 -1 0   1 0  -2  0}\
		southT {0 0  1 0  -1 0   0 -1}\
		southL {0 0  1 0  -1 0  -1 -1}\
		southJ {0 0  1 0  -1 0   1 -1}\
		southS {0 -1 -1 -1  0 0  1 0}\
		southZ {0 -1  1 -1  0 0 -1 0}\
		westI {0 0  0 1  0 2    0 -1}\
		westT {0 0  0 1  0 -1  -1 0}\
		westL {0 0  0 1  0 -1  -1 1}\
		westJ {0 0  0 1  0 -1  -1 -1}\
		westS {-1 0  -1 1  0 0  0 -1}\
		westZ {-1 0  -1 -1  0 0  0 1}\
		northoffset {{0 0} {0 0}  {0 0}  {0 0}  {0 0}}\
		eastoffset  {{0 0} {1 0}  {1 -1}  {0 2} {1 2}}\
		southoffset {{0 0} {0 0}  {0 0}  {0 0}  {0 0}}\
		westoffset  {{0 0} {-1 0} {-1 -1} {0 2} {-1 2}}\
		Inorthoffset {{0 0}   {-1 0} {2 0} {-1 0} {2 0}}\
		Ieastoffset  {{-1 0}  {0 0}  {0 0} {0 1} {0 -2}}\
		Isouthoffset {{-1 1} {1 1} {-2 1} {1 0}  {-2 0}}\
		Iwestoffset  {{0 1}  {0 1} {0 1}  {0 -1}  {0 2}}\
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
					($matrix(HEIGHT) - $matrix(BUFFER))
					* $game(cellsize)
					+ $game(skyline)
				}]\
			-width [expr {
					$matrix(WIDTH) * $game(cellsize)
					+ 1
				}]\
			-background grey\
			-takefocus true

	set originy [$widget(matrix) cget -height]
	# initialise grid which will be filled in by pieces during gameplay
	for {set y 0} {$y < $matrix(HEIGHT)} {incr y} {
		for {set x 0} {$x < $matrix(WIDTH)} {incr x} {
			$widget(matrix) create rectangle\
					[expr {$x * $game(cellsize)} + 1]\
					[expr {$originy - (
						($y) * $game(cellsize))
					}]\
					[expr {($x + 1) * $game(cellsize)}\
						+ 1]\
					[expr {$originy - (
						($y + 1) * $game(cellsize))
					}]\
					-tags "cell ($x,$y)"
		}
	}

	# piece preview
	ttk::labelframe $widget(previewlabel) -text NEXT
	canvas $widget(preview) \
			-width [expr {$game(cellsize) * 4}]\
			-height [expr {$game(cellsize) * 4}]\
			-background grey

	# TODO add graphics for all pieces, and simply hide/reveal them
	# as they appear in the queue
if 0 {
	for {set y 0} {$y < 4} {incr y} {
		for {set x 0} {$x < 4} {incr x} {
			$widget(preview) create rectangle\
					[expr {$x * $game(cellsize) + 1}]\
					[expr {$y * $game(cellsize) + 1}]\
					[expr {($x + 1) * $game(cellsize) + 1}]\
					[expr {($y + 1) * $game(cellsize) + 1}]\
					-tags {cell}
		}
	}
}
	pack $widget(preview) -padx 2 -pady 2

	# scoreboard (stats)
	ttk::labelframe $widget(stats) -text STATS
	ttk::label $widget(score) -text "Score: 0"
	ttk::label $widget(cleared) -text "Cleared: 0/0"
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
	button $widget(options) -text "Options" -command [namespace code {
		toggle_animation
	}]
	button $widget(about) -text "About" -command [namespace code {
		action_notify {(c) 2024 Rudy "dther" Dellomas III. Not authorised by TTC whatsoever. As-is, No Warranty, No Refunds.}
	}]
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

# TODO these will probably be removed at some point
proc toggle_animation {} {
	variable game
	set game(animate) [expr !$game(animate)]
	action_notify "Animation set to $game(animate). (i don't know why it's slow on windows)"
}

proc action_notify {str} {
	variable game
	set game(lastaction) $str
	update_stats
}

# initialise matrix data structure
# EMPTYROW: a list of length $matrix(WIDTH) containing empty strings ({})
proc reset_matrix {} {
	variable matrix

	array set matrix {
		fallcenter {}
		fallpiece {}
		clearedlines {}
	}
	set matrix(EMPTYROW) [lrepeat $matrix(WIDTH) {}]
	for {set y 0} {$y < $matrix(HEIGHT)} {incr y} {
		set matrix(row$y) $matrix(EMPTYROW)
	}
}

# returns true if $matrix(row$y) is empty
proc matrix_row_empty {y} {
	variable matrix
	foreach cell $matrix(row$y) {
		if {$cell != {}} {return false}
	}
	return true
}

# delete lines named in $matrix(clearedlines),
# shifting down rows above to fill gaps
proc matrix_clear_lines {} {
	variable matrix

	# start at the top (so as to avoid shifting higher cleared lines)
	set hitlist [lsort -integer -decreasing $matrix(clearedlines)]
	foreach line $hitlist {
		for {set y $line} {$y < $matrix(HEIGHT)} {incr y} {
			set above [expr {$y + 1}]
			if {$above >= $matrix(HEIGHT)} {
				set rowabove $matrix(EMPTYROW)
			} else {
				set rowabove $matrix(row$above)
			}
			set matrix(row$y) $rowabove
		}
	}
	set matrix(clearedlines) {}
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
		goal 10
		b2b false
	}
	set game(basefallms) $game(startfallms)
	set game(softdropms) [expr {round($game(startfallms)/20)}]

	# reset all cells
	reset_matrix
	$widget(matrix) itemconfigure cell -fill {}
	update_stats

	# seed PRNG
	if {$game(seed) == -1} {
		# harvest entropy from the decaying universe
		expr {srand([clock milliseconds])}
	} else {
		expr {srand($game(seed))}
	}
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
	$widget(cleared) configure -text "Cleared: $game(cleared)/$game(goal)"
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

	set kicks [get_piece_kicks $game(piece) $game(piecefacing) $newfacing]
	foreach kick $kicks {
		set trycenter [lmap center $matrix(fallcenter) shift $kick {
			expr {$center + $shift}
		}]
		if {[valid_move {*}$trycenter $newpiece]} {
			set matrix(fallcenter) $trycenter
			set game(piecefacing) $newfacing
			set matrix(fallpiece) $newpiece
			redraw
			break
		}
	}

	# TODO if a T piece manages to rotate to a valid position after five tries,
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

# The explanation for this is complicated.
# The best explanation available is at the following Tetris Wiki link:
# https://tetris.wiki/Super_Rotation_System#How_Guideline_SRS_Really_Works
# 
# Note the following differences:
# - Piece facings are notated as described in the Tetris Guidelines:
#   0 = north, R = east, 2 = south, L = west.
proc get_piece_kicks {piecename currentfacing newfacing} {
	variable piece
	if {$piecename == "O"} {return -code 1 "O piece can't rotate."}
	if {$piecename == "I"} {
		set startoffsets $piece(I${currentfacing}offset)
		set endoffsets $piece(I${newfacing}offset)
	} else {
		set startoffsets $piece(${currentfacing}offset)
		set endoffsets $piece(${newfacing}offset)
	}

	# rotating makes my head spin
	return [lmap start $startoffsets end $endoffsets {
		lmap s $start e $end {expr $s - $e}
	}]
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
			tailcall lock_phase
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
		lset matrix(fallcenter) 1 [expr [lindex $matrix(fallcenter) 1] - 1]
		award_points harddrop
	}
	redraw
	lock_piece
}

# add new piece to the queue
proc next_piece {} {
	variable game
	variable piece
	variable widget

	# TODO make this a queue to allow multiple piece previews
	# TODO implement bag randomisation
	set rand [expr round(rand() * 7) % 7]
	set game(nextqueue) [lindex $piece(list) $rand]

	# FIXME draw preview (broken due to changes in canvas logic)
}

# update widget(matrix) based on new game state
proc redraw {} {
	variable game
	variable matrix
	variable widget
	variable piece

	# TODO this is quite a heavy operation. need to start profiling
	# tag cells in matrix
	for {set y 0} {$y < $matrix(HEIGHT)} {incr y} {
		for {set x 0} {$x < $matrix(WIDTH)} {incr x} {
			set cell [lindex $matrix(row$y) $x]
			if {$cell != {}} {
				$widget(matrix) itemconfigure ($x,$y)\
						-tags "($x,$y) $cell cell"
			} else {
				$widget(matrix) itemconfigure ($x,$y)\
						-tags "($x,$y) empty cell"
			}
		}
	}

	# tag falling piece
	$widget(matrix) itemconfigure falling -fill {}
	tag_piece $widget(matrix) \
		falling $matrix(fallcenter) $matrix(fallpiece)

	# apply colors
	$widget(matrix) itemconfigure empty -fill {}
	$widget(matrix) itemconfigure falling -fill $piece($game(piece)color)
	foreach piecetag $piece(list) {
		$widget(matrix) itemconfigure $piecetag \
				-fill $piece(${piecetag}color)
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
		$canvas addtag $tag withtag "($x,$y)"
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
		if {$x >= $matrix(WIDTH) || $x < 0 || $y < 0 || $y >= $matrix(HEIGHT)} {
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

	return [expr {[lindex $matrix(row$y) $x] != {}}]
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
	lset nextfall 1 [expr [lindex $matrix(fallcenter) 1] - 1]

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

# Level up!
proc level_up {} {
	variable game

	if {$game(level) >= $game(levelcap)} {return}
	incr game(level)
	# XXX implements the Fixed Goal levelling system
	set game(goal) [expr {$game(level) * 10}]

	# speed up the game
	# there's probably an interger-based way of calculating this...
	set game(basefallms) [expr {round(
					(0.8 - ($game(level) - 1) * 0.007)
					** ($game(level) - 1)
					* 1000)}]
	set game(softdropms) [expr {round($game(basefallms)/20)}]
	set game(fallms) $game(basefallms)
	set game(softdropped) false
	set game(lastaction) "Level Up!"
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
	set matrix(fallcenter) $matrix(GENERATE)
	set matrix(fallpiece) $piece($game(piece))
	if {[block_out]} {
		tailcall game_over
	}

	# if space is available, immediately fall one block down
	# (As stated by the Tetris Guidelines.)
	if {[can_fall]} {
		lset matrix(fallcenter) 1 [expr [lindex $matrix(fallcenter) 1] - 1]
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
	set matrix(fallcenter) [list [lindex $matrix(fallcenter) 0] [expr [lindex $matrix(fallcenter) 1] - 1]]
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

	# mark occupied cells in $matrix
	foreach {x y} $matrix(fallpiece) {
		incr x [lindex $matrix(fallcenter) 0]
		incr y [lindex $matrix(fallcenter) 1]
		lset matrix(row$y) $x $game(piece)
	}

	redraw
	# if the falling piece landed entirely inside buffer zone, game over
	if {[lock_out]} {
		tailcall game_over
	}
	# TODO check for t-spins

	# XXX in multiplayer, this is when incoming attack lines would appear.
	tailcall pattern_phase
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
		if {[lsearch -exact $checklines $line] == -1} {
			lappend checklines [expr $line]
		}
	}

	# check for line clears
	set matrix(clearedlines) {}
	foreach line $checklines {
		if {[lsearch -exact $matrix(clearedlines) $line] != -1} {
			continue
		}
		set cells $matrix(row$line)
		set clear true
		foreach cell $cells {
			if {$cell == {}} {
				set clear false
				break
			}
		}
		if {$clear} {
			lappend matrix(clearedlines) $line
		}
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
	foreach y $matrix(clearedlines) {
		for {set x 0} {$x < [llength $matrix(row$y)]} {incr x} {
			$widget(matrix) itemconfigure "($x,$y)" -fill white
		}
	}

	# Eliminate
	matrix_clear_lines

	complete_phase
}

# update stat counters, then return to gen_phase
proc complete_phase {} {
	variable game

	if {$game(cleared) >= $game(goal)} {
		level_up
	}
	update_stats
	redraw

	gen_phase
}

init
} ;# end of namepace eval Tketris
