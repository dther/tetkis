#!/usr/bin/env wish

# tetkis.tcl
# (c) 2024 Rudy Dellomas III <dther+tetkis@dther.xyz>
#
# TeTkis: A simple Tetris clone for Tcl/Tk 8.6 <=
#
# TeTkis is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the
# Free Software Foundation, version 3.
# 
# TeTkis is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License along with this program.
# If not, see <https://www.gnu.org/licenses/>.

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
namespace eval TeTkis { ;#namespace encapsulates this file

variable game
variable piece
variable matrix
variable widget

proc init {} {
	variable game
	variable option
	variable piece
	variable widget
	variable matrix

	# XXX import a custom theme
	set LIBPATH [file join [file dirname [info script]] lib]
	source [file join $LIBPATH azure-ttk-theme azure.tcl]

	array set option {
		das 200
		arr 60
		seed -1
	}

	# TODO separate options from game state
	# constants + settings
	# name: name of app
	# cellsize: visual size of cells in pixels
	# seed: seed given to "expr srand(n)" at new_game
	# holding: if true, allow pieces to be "held" in the holdqueue
	# holdused: if true, hold queue cannot be used until the next piece.
	# holdqueue: list containing piece that is being held, if any
	# maxlockmoves: number of moves allowed during the lock phase,
	#               after which piece is locked immediately
	# bagrandom: if true, pick new pieces with the "bag system"
	# bag: virtual bag of 7 pieces, refilled when empty
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
		name TeTkis
		cellsize 25
		queuesize 7
		holding false
		seed -1
		maxlockmoves 15
		bagrandom true
		skyline 10
		startfallms 1000
		lockms 500
		levelcap 15
		bag {}
		nextqueue {}
		holdused false
		holdqueue {}
		basefallms 1000
		softdropms 50
		fallms 1000
		lockmovesleft 15
		lowestfall 0
		checktspin false
		kicktspin false
		fallafter false
		lockafter false
		softdropping false
		softdropped false
		locked true
		piece {}
		piecefacing {}
		lastaction {}
		score 0
		cleared 0
		level 1
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

	array set piece {
		list {L J I O S Z T}
		facings {north east south west}
		Lcolor orange
		Jcolor blue
		Icolor cyan
		Ocolor yellow
		Scolor green
		Zcolor red
		Tcolor magenta
		O {0 0  1 0  0 1  1 1}
		I {0 0 -1 0  1 0  2 0}
		T {0 0  1 0 -1 0  0 1}
		L {0 0  1 0 -1 0  1 1}
		J {0 0  1 0 -1 0 -1 1}
		S {0 0 -1 0  0 1  1 1}
		Z {0 0  1 0  0 1 -1 1}
		eastI {0 0  0  1  0 -1  0 -2}
		eastT {0 0  0  1  0 -1  1  0}
		eastL {0 0  0  1  0 -1  1 -1}
		eastJ {0 0  0  1  0 -1  1  1}
		eastS {0 0  0  1  1  0  1 -1}
		eastZ {0 0  0 -1  1  0  1  1}
		southI {0 0 -1 0   1 0  -2  0}
		southT {0 0  1 0  -1 0   0 -1}
		southL {0 0  1 0  -1 0  -1 -1}
		southJ {0 0  1 0  -1 0   1 -1}
		southS {0 -1 -1 -1  0 0  1 0}
		southZ {0 -1  1 -1  0 0 -1 0}
		westI {0 0  0 1  0 2    0 -1}
		westT {0 0  0 1  0 -1  -1 0}
		westL {0 0  0 1  0 -1  -1 1}
		westJ {0 0  0 1  0 -1  -1 -1}
		westS {-1 0  -1 1  0 0  0 -1}
		westZ {-1 0  -1 -1  0 0  0 1}
		northoffset {{0 0} {0 0}  {0 0}  {0 0}  {0 0}}
		eastoffset  {{0 0} {1 0}  {1 -1}  {0 2} {1 2}}
		southoffset {{0 0} {0 0}  {0 0}  {0 0}  {0 0}}
		westoffset  {{0 0} {-1 0} {-1 -1} {0 2} {-1 2}}
		Inorthoffset {{0 0}   {-1 0} {2 0} {-1 0} {2 0}}
		Ieastoffset  {{-1 0}  {0 0}  {0 0} {0 1} {0 -2}}
		Isouthoffset {{-1 1} {1 1} {-2 1} {1 0}  {-2 0}}
		Iwestoffset  {{0 1}  {0 1} {0 1}  {0 -1}  {0 2}}
	}

	# UI elements
	array set widget {
		matrix .matrix
		holdframe .holdf
		hold .holdf.hold
		previewframe .previewf
		preview .previewf.preview
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
	set visiblerows [expr {$matrix(HEIGHT) - $matrix(BUFFER) + 1}]
	# initialise grid which will be filled in by pieces during gameplay
	for {set y 0} {$y < $visiblerows} {incr y} {
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
	ttk::labelframe $widget(previewframe) -text NEXT
	canvas $widget(preview) \
			-width [expr {$game(cellsize) * 4}]\
			-background grey

	init_previews
	pack $widget(preview) -padx 2 -pady 2 -expand 1 -fill both

	# hold piece view
	ttk::labelframe $widget(holdframe) -text HOLD
	canvas $widget(hold) \
			-width [expr {$game(cellsize) * 4}]\
			-height [expr {$game(cellsize) * 4}]\
			-background grey

	init_hold
	pack $widget(hold) -padx 2 -pady 2 -fill both

	# scoreboard (stats)
	ttk::labelframe $widget(stats) -text STATS
	ttk::label $widget(score) -text "Score: 0"\
				-wraplength [expr {4*$game(cellsize)}]
	ttk::label $widget(cleared) -text "Cleared: 0/0"\
				-wraplength [expr {4*$game(cellsize)}]
	ttk::label $widget(lastaction) -text {}\
				-wraplength [expr {4*$game(cellsize)}]
	ttk::label $widget(level) -text "Level: 0"\
				-wraplength [expr {4*$game(cellsize)}]
	pack $widget(score) -fill x
	pack $widget(cleared) -fill x
	pack $widget(level) -fill x
	pack $widget(lastaction) -fill x -side bottom

	# game menu
	ttk::labelframe $widget(gamemenu) -text MENU
	ttk::button $widget(newgame) -text "New Game"\
				-command [namespace code new_game]
	ttk::button $widget(options) -text "Options" -command [namespace code {
		open_options_window
	}]
	ttk::button $widget(about) -text "About" -command [namespace code {
		tk_messageBox -default ok -message "TeTkis v1.0.0" -title "About TeTkis"\
-detail {Except for the Azure ttk theme:
(c) 2024 Rudy Dellomas III

TeTkis is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3.

TeTkis is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.

---
Azure theme for ttk
https://github.com/rdbende/Azure-ttk-theme/

Copyright (c) 2021 rdbende, redistributed under the terms of the MIT License.}}]
	pack $widget(newgame) -fill x
	pack $widget(options) -fill x
	pack $widget(about) -fill x

	# place elements
	grid $widget(matrix) -row 0 -column 1 -rowspan 3 -padx 2 -pady 2
	grid $widget(previewframe) -row 0 -column 2 -rowspan 2 -padx 2 -pady 2 -sticky nsew
	grid $widget(holdframe) -row 0 -column 0 -padx 2 -pady 2 -sticky nsew
	grid $widget(gamemenu) -row 2 -column 2 -padx 2 -pady 2 -sticky nsew
	grid $widget(stats) -row 1 -column 0 -rowspan 2 -padx 2 -pady 2 -sticky nsew
	grid rowconfigure . 1 -weight 1

	# ensure window is right size
	wm title . $game(name)
	wm withdraw .
	wm resizable . 0 0
	wm deiconify .

	# bindings
	variable binds
	array set binds {
		MoveLeft {Left a}
		MoveRight {Right d}
		HardDrop {Up space}
		SoftDrop {Down s}
		RotateRight {x w e}
		RotateLeft {z q}
		Hold {Shift_L Shift_R}
	}

	apply_binds

	bind $widget(matrix) <<MoveLeft>> [namespace code {move_piece left}]
	bind $widget(matrix) <<MoveRight>> [namespace code {move_piece right}]
	bind $widget(matrix) <<RotateRight>> [namespace code {rotate_piece right}]
	bind $widget(matrix) <<RotateLeft>> [namespace code {rotate_piece left}]
	bind $widget(matrix) <<SoftDropPress>> [namespace code {soft_drop true}]
	bind $widget(matrix) <<SoftDropRelease>> [namespace code {soft_drop false}]
	bind $widget(matrix) <<Hold>> [namespace code {hold_piece}]
	bind $widget(matrix) <<HardDrop>> [namespace code {hard_drop}]

	# focus the matrix on click
	bind . <1> [namespace code {variable widget ; focus $widget(matrix)}]

	# autorepeat
	# XXX system autorepeat currently remains on
	# (It's normally much slower than default settings)
	#exec xset r off
	variable lastautostart {}
	bind all <<MoveLeft>> [namespace code {start_autorepeat %k %E}]
	bind all <<MoveRight>> [namespace code {start_autorepeat %k %E}]
	bind all <Any-KeyRelease> [namespace code {stop_autorepeat %k}]
	#bind . <Destroy> {exec xset r on}
}

# Binds keys to gameplay virtual events according to $binds array
proc apply_binds {} {
	variable binds
	set bindsdict [array get binds]
	foreach {event keys} $bindsdict {
		event delete <<$event>>
		foreach key $keys {
			catch {event add <<$event>> <$key>}
		}
	}

	# Soft Drop is a special case.
	set softdropkeys $binds(SoftDrop)
	event delete <<SoftDropPress>>
	event delete <<SoftDropRelease>>
	foreach key $softdropkeys {
		catch {event add <<SoftDropPress>> <$key>}
		catch {event add <<SoftDropRelease>> <KeyRelease-$key>}
	}
}

# software autorepeat implementation (to allow user configuration)
proc start_autorepeat {keycode sendevent} {
	variable option
	variable lastautostart
	if {$sendevent} {return}
	if {$lastautostart != $keycode} {
		stop_autorepeat $lastautostart
	}
	set lastautostart $keycode
	after cancel [namespace code "do_repeat $keycode"]
	after $option(das) [namespace code "do_repeat $keycode"]
}

proc stop_autorepeat {keycode} {
	after cancel [namespace code "do_repeat $keycode"]
}

proc do_repeat {keycode} {
	variable widget
	variable option
	after cancel [namespace code "do_repeat $keycode"]
	after [expr {round(1000/$option(arr))}] [namespace code "do_repeat $keycode"]
	event generate $widget(matrix) <KeyPress> -keycode $keycode -sendevent 1
}

# create and display options window
proc open_options_window {} {
	variable widget
	variable option
	# if options window already exists, focus it and return
	if {![catch {focus $widget(optwin)}]} { return }
	array set widget {
		optwin .options
		opttab .options.nb
		optframe .options.nb.f
		optfields .options.nb.f.f
			themelabel .options.nb.f.f.themelabel
			themeselect .options.nb.f.f.themeselect
			daslabel .options.nb.f.f.dasl
			dasfield .options.nb.f.f.das
			arrlabel .options.nb.f.f.arrl
			arrfield .options.nb.f.f.arr
			seedlabel .options.nb.f.f.seedl
			seedfield .options.nb.f.f.seed
			binds .options.nb.f.f.binds
		optsep .options.nb.f.sep
		optbuttons .options.nb.f.b
			optok	.options.nb.f.b.ok
			optapply .options.nb.f.b.apply
			optcancel .options.nb.f.b.cancel
		optsavelabel .options.nb.f.savelabel
	}

	toplevel $widget(optwin)
	ttk::notebook $widget(opttab)
	ttk::frame $widget(optframe)
	ttk::frame $widget(optfields)
	ttk::separator $widget(optsep) -orient horizontal
	ttk::frame $widget(optbuttons)

	pack $widget(opttab) -expand 1 -fill both
	$widget(opttab) add $widget(optframe) -text Options -padding 10

	grid anchor $widget(optframe) n
	grid $widget(optsep) -row 1 -column 0 -columnspan 2 -sticky nsew -pady 5
	grid $widget(optfields) -row 0 -column 0 -columnspan 2 -sticky nsew
	grid rowconfigure $widget(optframe) 0 -weight 1 -uniform a
	grid columnconfigure $widget(optframe) 0 -weight 1

	# Option Entry Fields

	# set theme
	ttk::label $widget(themelabel) -text "Theme: "
	ttk::combobox $widget(themeselect) -values [ttk::style theme names] -state readonly -takefocus 1
	$widget(themeselect) set [ttk::style theme use]

	# set arr/das
	ttk::label $widget(arrlabel) -text "Auto Repeat Rate: "
	ttk::label $widget(daslabel) -text "Delay Auto Shift: "
	ttk::spinbox $widget(arrfield) -from 0 -to 1000 -increment 5 -format "%.0fHz" -validate key -validatecommand {
		set newval [string trim %P HhZz]
		if {[string is double $newval]} {
			return 1
		}
		return 0
	} -width 6 -takefocus 1
	ttk::spinbox $widget(dasfield) -from 0 -to 1000 -increment 10 -format "%.0fms" -validate key -validatecommand {
		set newval [string trim %P MmSs]
		if {[string is double $newval]} {
			return 1
		}
		return 0
	} -width 6 -takefocus 1
	$widget(arrfield) set $option(arr)Hz
	$widget(dasfield) set $option(das)ms

	# seed
	ttk::label $widget(seedlabel) -text "Seed:\n(-1 = new every game)"
	ttk::spinbox $widget(seedfield) -from -1 -to Inf -increment 1 -takefocus 1 -validate focus -validatecommand {
		set newseed %P
		if {[string is integer -strict $newseed]} {
			return 1
		}
		return 0
	} -invalidcommand [namespace code {
		variable widget
		variable option
		$widget(seedfield) set $option(seed)
	}]
	$widget(seedfield) set $option(seed)

	# set controls - XXX this one is complicated
	ttk::labelframe $widget(binds) -text CONTROLS
	variable binds
	set row 0
	set removeinvalidkeys [list {action} {
		variable widget
		variable binds
		set keys %P
		# excise invalid keysyms
		set keys [lmap key $keys {
			if {[catch {event add <<DUMMYNOP>> <$key>}]} {
				continue
			}
			set key
		}]
		if {[llength $keys] >= 1} {
			$widget(${action}field) delete 0 end
			$widget(${action}field) insert 0 $keys
		} else {
			$widget(${action}field) delete 0 end
			$widget(${action}field) insert 0 $binds($action)
		}
	} [namespace current]]
	# put the control fields in a logical order
	foreach {action} {MoveLeft MoveRight RotateLeft RotateRight Hold SoftDrop HardDrop} {
		set keys $binds($action)
		set widget(${action}label) $widget(binds).label${action}
		set widget(${action}field) $widget(binds).field${action}

		ttk::label $widget(${action}label) -text $action
		# Value of field must be a valid Tcl list containing one or more valid keysyms
		# if invalid, return to the currently set value of $binds($action)
		ttk::entry $widget(${action}field) -text $action -validate focus -validatecommand {
			set keys %P
			foreach key $keys {
				if {[catch {event add <<DUMMYNOP>> <$key>}]} {
					return 0
				}
			}
			return 1
		} -invalidcommand "apply {$removeinvalidkeys} $action"

		# init. to the current values
		$widget(${action}field) delete 0 end
		$widget(${action}field) insert 0 $binds($action)

		grid $widget(${action}label) -column 0 -row $row -sticky w
		grid $widget(${action}field) -column 1 -row $row -sticky we
		incr row
	}

	# TODO more game settings
	# set hold on/off
	# set preview queue

	# arrange fields
	set padding "-padx 2 -pady 2"
	grid anchor $widget(optfields) n
	grid columnconfigure $widget(optfields) 1 -weight 1 -uniform a
	grid columnconfigure $widget(optfields) 3 -weight 1 -uniform a
	grid $widget(themelabel) -column 0 -row 0 -sticky w {*}$padding
	grid $widget(themeselect) -column 1 -row 0 -columnspan 3 -sticky we {*}$padding
	grid $widget(arrlabel) -column 0 -row 1 -sticky w {*}$padding
	grid $widget(arrfield) -column 1 -row 1 -sticky w {*}$padding
	grid $widget(daslabel) -column 2 -row 1 -sticky w {*}$padding
	grid $widget(dasfield) -column 3 -row 1 -sticky w {*}$padding
	grid $widget(seedlabel) -column 0 -row 2 -sticky w -columnspan 2 {*}$padding
	grid $widget(seedfield) -column 2 -row 2 -sticky we -columnspan 2 {*}$padding
	grid $widget(binds) -column 0 -row 3 -columnspan 4

	# Option buttons: ok apply cancel
	grid $widget(optbuttons) -row 2 -column 1
	ttk::button $widget(optok) -text Ok -command [namespace code {
		apply_options
		exit_options
	}]
	ttk::button $widget(optapply) -text Apply -command [namespace code {apply_options}]
	ttk::button $widget(optcancel) -text Cancel -command [namespace code {exit_options}]
	grid $widget(optok) -row 0 -column 0 -padx 2
	grid $widget(optapply) -row 0 -column 1 -padx 2
	grid $widget(optcancel) -row 0 -column 2 -padx 2

	# becomes "Options Saved" when options are applied
	ttk::label $widget(optsavelabel) -width [string length "Options Saved"]
	grid $widget(optsavelabel) -row 2 -column 0 -sticky e

	wm withdraw $widget(optwin)
	wm resizable $widget(optwin) 0 0
	wm deiconify $widget(optwin)
}

proc apply_options {} {
	variable widget
	variable option

	# set theme
	set theme [$widget(themeselect) get]
	# XXX special cases for azure
	if {[string match azure-dark $theme]} {
		set_theme dark
	} elseif {[string match azure-light $theme]} {
		set_theme light
	} else {
		ttk::style theme use $theme
	}

	# set arr/das
	set newarr [string trim [$widget(arrfield) get] HhZz]
	set newdas [string trim [$widget(dasfield) get] MmSs]
	if {$newarr < 1} {
		set newarr 1
	} elseif {$newdas > 1000} {
		set newdas 1000
	}
	set option(arr) $newarr
	$widget(arrfield) set $option(arr)Hz

	if {$newdas < 1} {
		set newdas 1
	} elseif {$newdas > 1000} {
		set newdas 1000
	}
	set option(das) $newdas
	$widget(dasfield) set $option(das)ms

	# set seed
	set newseed [$widget(seedfield) get]
	if {![string is integer -strict $newseed]} {
		set newseed $option(seed)
	}
	set option(seed) $newseed
	$widget(seedfield) set $option(seed)

	# set binds table
	variable binds
	foreach {action keys} [array get binds] {
		set binds($action) [$widget(${action}field) get]
		$widget(${action}field) delete 0 end
		$widget(${action}field) insert 0 $binds($action)
	}
	apply_binds

	$widget(optsavelabel) configure -text "Options Saved"
}

proc exit_options {} {
	variable widget
	destroy $widget(optwin)
}

# Add a view for the piece currently inside the hold queue
proc init_hold {} {
	variable widget
	variable game
	init_view $widget(hold) 0 [expr $game(cellsize)*2] [expr $game(cellsize)*2]\
				[expr $game(cellsize) * 0.95]
}

# add previews for all pieces, hidden/revealed when needed
# Each has two tags: "q$index$piece" and "preview"
# This way, updating the preview is a simple process:
# 1. $widget(preview) itemconfigure preview -state hidden
# 2. $widget(preview) itemconfigure q$index$piece -state normal
#    (for each piece in $game(nextqueue))
proc init_previews {} {
	variable widget
	variable game
	variable piece

	# XXX Getting this to look right was a LOT of trial and error.
	set icy [expr {round([$widget(preview) cget -height]/5)}]

	set cx [expr {$game(cellsize) * 2}]
	set cy [expr {round($game(cellsize) * 1.5)}]
	init_view $widget(preview) 0 $cx $cy [expr {$game(cellsize) * 0.95}]

	incr cy $icy
	init_view $widget(preview) 1 $cx $cy [expr {$game(cellsize) * 0.66}]

	incr cy $icy
	init_view $widget(preview) 2 $cx $cy [expr {$game(cellsize) * 0.66}]

	incr cy $icy
	init_view $widget(preview) 3 $cx $cy [expr {$game(cellsize) * 0.66}]

	incr cy $icy
	init_view $widget(preview) 4 $cx $cy [expr {$game(cellsize) * 0.5}]

	incr cy $icy
	init_view $widget(preview) 5 $cx $cy [expr {$game(cellsize) * 0.5}]

	incr cy $icy
	init_view $widget(preview) 6 $cx $cy [expr {$game(cellsize) * 0.5}]
}

# Initialises a "piece view" in a canvas widget that can be toggled on or off
# drawing pieces in $widget(preview) centered at the position (cx, cy).
# cellsize can be used to specify that the preview should be smaller.
proc init_view {canvas index cx cy cellsize} {
	set newpreview [list {index name centerx centery cellsize} {
		variable piece
		upvar canvas canvas
		foreach {x y} $piece($name) {
			$canvas create rectangle \
			[expr $centerx + $x * $cellsize]\
			[expr $centery + -$y * $cellsize]\
			[expr $centerx + ($x+1) * $cellsize]\
			[expr $centery + (-$y+1) * $cellsize]\
					-tags "preview q$index$name"\
					-fill $piece(${name}color)\
					-state hidden
		}
	} [namespace current]]

	# adjust cx and cy for piece I
	set adjustedx [expr {$cx - $cellsize}]
	set adjustedy [expr {$cy - $cellsize/2}]

	apply $newpreview $index I $adjustedx $adjustedy $cellsize

	# change the y offset for pieces that are two cells tall
	set adjustedy $cy
	apply $newpreview $index O $adjustedx $adjustedy $cellsize

	# change the x offset for pieces that are 3 cells wide
	set adjustedx [expr {$cx - $cellsize/2}]
	apply $newpreview $index T $adjustedx $adjustedy $cellsize
	apply $newpreview $index L $adjustedx $adjustedy $cellsize
	apply $newpreview $index J $adjustedx $adjustedy $cellsize
	apply $newpreview $index S $adjustedx $adjustedy $cellsize
	apply $newpreview $index Z $adjustedx $adjustedy $cellsize
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
	variable option

	# cancel all timers
	cancel_lock
	cancel_fall

	# reset game and matrix
	array set game {
		checktspin false
		kicktspin false
		holdused false
		holdqueue {}
		fallms 1000
		lockms 500
		lockmovesleft 15
		lowestfall 0
		fallafter false
		lockafter false
		softdropping false
		softdropped false
		locked true
		bag {}
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

	# TODO ensure the size stays consistent somehow
	# shift windows around based on game mode options
if 0 {
	if {!$game(holding)} {
		grid forget . $widget(holdframe)
	}
}

	# reset all cells
	reset_matrix
	$widget(matrix) itemconfigure cell -fill {}
	update_stats

	# seed PRNG
	set game(seed) $option(seed)
	if {$game(seed) == -1} {
		# harvest entropy from the decaying universe
		expr {srand([clock milliseconds])}
	} else {
		expr {srand($game(seed))}
	}
	refill_next_queue

	focus $widget(matrix)
	gen_phase
}

# award points according to the Tetris scoring table
proc award_points {action {tspin false}} {
	variable game

	# T-spins
	switch -- $tspin {
		true {set actionstr "T-Spin "}
		mini {set actionstr "Mini T-Spin "}
		false {set actionstr {}}
		default {return -code 1 "invalid tspin value: $tspin"}
	}
	switch -- $action {
		0 {
			switch -- $tspin {
				true {set base 400}
				mini {set base 100}
				default {return -code error "Invalid action $action"}
			}
		}
		1 {
			set actionstr "${actionstr}Single"
			switch -- $tspin {
				false {set base 100}
				mini {set base 200}
				true {set base 800}
			}
		}
		2 {
			set actionstr "${actionstr}Double"
			if {!$tspin} {
				set base 800
			} else {
				set base 1200
			}
		}
		3 {
			set actionstr "${actionstr}Triple"
			if {!$tspin} {
				set base 500
			} else {
				set base 1600
			}
		}
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
		default {return -code 1 "Invalid action $action"}
	}

	set total [expr {$base * $game(level)}]
	set actionstr "$actionstr\n($base x $game(level)"
	if {$game(b2b) && $action != 0} {
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

# Hold the current piece.
# If there is no piece in the hold queue, the current piece is put into it,
# and a new piece is generated.
# If there is already a piece in the hold queue,
# the current piece enters the hold queue,
# and the piece previously in the queue is put into play as though
# it was newly generated via gen_phase.
proc hold_piece {} {
	variable game
	if {$game(locked) || $game(holdused)} {return}
	set game(holdused) true
	lappend game(holdqueue) $game(piece)
	if {[llength $game(holdqueue)] == 1} {
		tailcall gen_phase
	}
	tailcall gen_phase holdqueue
}

proc update_hold_view {} {
	variable widget
	variable game
	set piece [lindex $game(holdqueue) 0]
	$widget(hold) itemconfigure preview -state hidden
	$widget(hold) itemconfigure "q0$piece" -state normal
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
	set success false
	set tries 0
	foreach kick $kicks {
		incr tries
		set trycenter [lmap center $matrix(fallcenter) shift $kick {
			expr {$center + $shift}
		}]
		if {[valid_move {*}$trycenter $newpiece]} {
			# successful rotation
			set success true
			set matrix(fallcenter) $trycenter
			set game(piecefacing) $newfacing
			set matrix(fallpiece) $newpiece
			redraw

			# if we rotated into a lower spot than before,
			# give the piece more lockmoves
			if {[lindex $matrix(fallcenter) 1] < $game(lowestfall)} {
				set game(lockmovesleft) $game(maxlockmoves)
				lassign $matrix(fallcenter) _ game(lowestfall)
			} elseif {$game(lockafter) != false} {
				incr game(lockmovesleft) -1
			}
			# extend lock timer
			cancel_lock
			break
		}
	}

	# if no rotation occurred, don't recalculate fall/lock events
	if {!$success} {return}

	# if a T piece manages to rotate to a valid position after five tries,
	# and locks as a result, then it's a full (not mini) t-spin
	if {$tries >= 5 && $game(piece) == "T"} {
		set game(kicktspin) true
	}

	# check if rotation has caused piece to "lift"
	# (and therefore may cause it to go from locking to falling)
	if {[can_fall] && $game(fallafter) == false} {
		cancel_lock
		set game(fallafter) [after $game(fallms) [namespace code fall_phase]]
	} elseif {![can_fall]} {
		if {$game(piece) == "T"} {set game(checktspin) true}
		cancel_fall
		tailcall lock_phase
	}
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
	if {[valid_move {*}$newpos]} {
		set game(checktspin) false
		set game(kicktspin) false
		set matrix(fallcenter) $newpos
		redraw
		# any movement extends the lock timer
		if {$game(lockafter) != false} {
			cancel_lock
			incr game(lockmovesleft) -1
		}
		# re-check if we can fall
		if {[can_fall] && $game(fallafter) == false} {
			set game(fallafter) [after $game(fallms) [namespace code fall_phase]]
			return
		}

		# if we can't fall, check if we need to be locked
		if {![can_fall]} {
			cancel_fall
			lock_phase
		}
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

# returns the first element in a list variable after deleting it
proc lpop {name} {
	upvar $name list 
	set popped [lindex $list 0]
	set list [lrange $list 1 end]
	return $popped
}

# keep the Next Queue filled to $game(queuesize)
proc refill_next_queue {} {
	variable game
	variable piece
	variable widget

	while {[llength $game(nextqueue)] < $game(queuesize)} {
		lappend game(nextqueue) [new_piece]
	}

	# draw preview
	$widget(preview) itemconfigure preview -state hidden
	for {set i 0} {$i < [llength $game(nextqueue)]} {incr i} {
		set p [lindex $game(nextqueue) $i]
		$widget(preview) itemconfigure "q$i$p" -state normal
	}
}

# Produces a new piece to feed the nextqueue.
proc new_piece {} {
	variable game
	variable piece

	if {!$game(bagrandom)} {
		return [lindex $piece(list) [expr round(rand() * 7) % 7]]
	}

	if {[llength $game(bag)] == 0} {
		refill_bag
	}
	return [lpop game(bag)]
}

# refill the bag with 7 pieces, then perform fischer-yates shuffle
proc refill_bag {} {
	variable game
	variable piece
	set game(bag) $piece(list)

	for {set i [llength $game(bag)]} {$i > 1} {incr i -1} {
		set rand [expr {round(rand() * $i) % $i}]
		set swap [expr {$i - 1}]
		if {$swap == $rand} {continue}
		set buf [lindex $game(bag) $swap]
		lset game(bag) $swap [lindex $game(bag) $rand]
		lset game(bag) $rand $buf
	}
}

# update widget(matrix) based on new game state
proc redraw {} {
	variable game
	variable matrix
	variable widget
	variable piece

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

	# tag ghost piece
	if {[can_fall]} {
		for {lassign $matrix(fallcenter) x y} {$y >= 0} {incr y -1} {
			if {![valid_move $x $y]} {
				break
			}
		}
		incr y
		tag_piece $widget(matrix) ghost "$x $y" $matrix(fallpiece)
	}

	# apply colors
	$widget(matrix) itemconfigure empty -fill {}
	$widget(matrix) itemconfigure ghost -fill "light grey"
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

	return [expr {
		$x < 0 || $y < 0
		|| $x >= $matrix(WIDTH) || $y >= $matrix(HEIGHT)
		|| ([lindex $matrix(row$y) $x] != {})
	}]
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

	redraw
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
# "queue" can be used to indicate whether the next piece is from the
# nextqueue or the hold queue
proc gen_phase {{queue nextqueue}} {
	variable game
	variable matrix
	variable piece

	# ensure these can't happen out of turn
	cancel_fall
	cancel_lock

	set game(piece) [lpop game($queue)]
	set game(piecefacing) north
	refill_next_queue
	update_hold_view

	# place the center of the piece at $matrix(generate)
	set matrix(fallcenter) $matrix(GENERATE)
	set matrix(fallpiece) $piece($game(piece))
	set game(lockmovesleft) $game(maxlockmoves)
	lassign $matrix(fallcenter) _ game(lowestfall)
	if {[block_out]} {
		tailcall game_over
	}

	# if space is available, immediately fall one block down
	# (As stated by the Tetris Guidelines.)
	if {[can_fall]} {
		lset matrix(fallcenter) 1 [expr [lindex $matrix(fallcenter) 1] - 1]
		incr game(lowestfall) -1
	}

	set game(locked) false
	redraw
	if {[can_fall]} {
		set game(fallafter) [after $game(fallms) [namespace code fall_phase]]
	} else {
		tailcall lock_phase
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

	set game(checktspin) false
	set game(kicktspin) false
	set game(softdropped) $game(softdropping)
	if {$game(softdropped)} {
		award_points softdrop
	}
	set matrix(fallcenter) [list [lindex $matrix(fallcenter) 0] [expr [lindex $matrix(fallcenter) 1] - 1]]
	redraw

	# if the piece falls to a new low, reset lockmovesleft
	if {[lindex $matrix(fallcenter) 1] < $game(lowestfall)} {
		set game(lockmovesleft) $game(maxlockmoves)
		lassign $matrix(fallcenter) _ game(lowestfall)
	}

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

	set game(locked) false

	# cancel any events that might be pending
	cancel_fall
	cancel_lock

	# lock immediately if moves are used up
	if {$game(lockmovesleft) == 0} {
		tailcall lock_piece
	}
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

	# if the falling piece landed entirely inside buffer zone, game over
	if {[lock_out]} {
		tailcall game_over
	}

	# check for t-spins
	set tspin false
	if {$game(checktspin) || $game(kicktspin)} {
		set tspin [check_tspin]
	}

	# XXX in multiplayer, this is when incoming attack lines would appear.
	tailcall pattern_phase $tspin
}

# Examines the area around $matrix(fallcenter) and checks if a T-Spin occurred.
# Returns one of three values:
# true: a T-Spin occurred.
# mini: A mini T-Spin occurred.
# false: no T-Spin occurred. 
proc check_tspin {} {
	variable matrix
	variable game
	# this table describes the blocks surrounding the T piece.
	# The values of each list correspond to A, B, C and D
	# from the guidelines.
	array set SIDE {
		north {{-1 1} {1 1} {-1 -1} {1 -1}}
		east  {{1 -1} {1 1} {-1 -1} {-1 1}}
		south {{-1 -1} {1 -1} {-1 1} {1 1}}
		west  {{-1 -1} {-1 1} {1 -1} {1 1}}
	}
	lassign $matrix(fallcenter) cx cy
	set sidecoords [lmap side $SIDE($game(piecefacing)) {
		lassign $side x y
		incr x $cx
		incr y $cy
		list $x $y
	}]
	lassign $sidecoords a b c d

	# check which of the four corners are occupied
	set ab 0
	set cd 0
	foreach {side} {a b c d} {
		if {![cell_occupied {*}[set $side]]} {continue}
		switch -- $side {
			a - b {incr ab}
			c - d {incr cd}
		}
	}

	# Now, check all possible conditions for a t-spin or t-spin mini.
	if {$ab + $cd < 3} {
		# not in T-Slot, no T-Spin
		return false
	} elseif {$ab == 2 || $game(kicktspin)} {
		# Sides A B and at least one of C/D are filled,
		# OR the T piece travelled very far to fit into this slot.
		# "True" T-Spin.
		return true
	} else {
		# Otherwise, Mini T-Spin.
		return mini
	}
}

# check for line clears, award points
proc pattern_phase {tspin} {
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
	# clearing no lines DOES NOT reset B2B
	# single, doubles and triples w/o a tspin DO reset B2B
	if {$linescleared != 0 && $linescleared != 4 && $tspin == false} {
		set game(b2b) false
	}

	# award points based on number of lines cleared
	if {$linescleared > 0} {
		incr game(cleared) $linescleared
		award_points $linescleared $tspin
	} elseif {$tspin != false} {
		# award T-Spins even if no lines are cleared
		award_points $linescleared $tspin
	}

	# Award B2B starting with the second action in the sequence
	if {$linescleared == 4 || ($tspin != false && $linescleared > 0)} {
		set game(b2b) true
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

	set game(holdused) false
	if {$game(cleared) >= $game(goal)} {
		level_up
	}
	update_stats
	redraw

	gen_phase
}

init
} ;# end of namepace eval TeTkis
