package main

import "core:fmt"
import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"
import "core:c"
import "core:thread"
import "core:math"

WIN_WIDTH :: 800
WIN_HEIGHT :: 600
FPS :: 30

FONT_WIDTH :: 14
FONT_HEIGHT :: 16
FONT_SIZE_MULT :: 1

OCTAVE_MIN :: 1
OCTAVE_MAX :: 7

MAX_VOICES :: 6
MAX_WAVEFORMS :: 4

KeyboardKeyData :: struct {
	down: bool,
	voice: int
}

running := true
win: ^sdl.Window
render: ^sdl.Renderer
event: sdl.Event
nextTick: u32
inputThread: ^thread.Thread

drawingWaveform := true
drawingKeyboard := true

font: ^ttf.Font
titleText: Text
voicesHeaderText: Text

keyboardKeys: [13]sdl.Keycode = {
	.a, // thank you odin :o
	.w,
	.s,
	.e,
	.d,
	.f,
	.t,
	.g,
	.y,
	.h,
	.u,
	.j,
	.k
}

keyboardKeyData: [13]KeyboardKeyData

octave: i32 = 4
keyboardKeysDown: []i32 // pressed key for each voice

// updating ui directly in the input thread is not working
// so it gets acknowledged and then handled in the main loop
uiUpdateReady: bool = true

main :: proc() {
	sdl.Init(sdl.INIT_VIDEO | sdl.INIT_AUDIO)
	defer sdl.Quit()

	// init video
	win = sdl.CreateWindow("Odin Synthesizer - Ari Bishop", sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED, WIN_WIDTH, WIN_HEIGHT, {})
	defer sdl.DestroyWindow(win)
	render = sdl.CreateRenderer(win, -1, {})
	defer sdl.DestroyRenderer(render)

	// init input
	inputThread = thread.create(handleInput)
	inputThread.init_context = context
	inputThread.user_index = 0
	thread.start(inputThread)
	defer thread.destroy(inputThread)

	for i in 0..<len(keyboardKeyData) {
		keyboardKeyData[i].voice = -1
	}

	initGui()
	defer quitGui()
	
	titleText = newText("Odin Synthesizer", COLOR_BLACK, COLOR_YELLOW)
	defer destroyText(titleText)

	// init audio
	initSynth()
	defer quitSynth()
	sdl.PauseAudioDevice(audioDevice, false)

	// default voice (synth handles deleting waveforms too!)
	waveforms: [dynamic]VoiceWaveform
	append(&waveforms, VoiceWaveform{Waveform.Sawtooth, 440, 1, 0.0})
	addVoice(waveforms, 0)
	addVoiceUI()
	addWaveformUI(0)

	for running {
		tick := sdl.GetTicks()
		if tick >= nextTick {
			nextTick = tick + 1000 / FPS
		}
		else {
			continue
		}

		updateUi()

		sdl.SetRenderDrawColor(render, 0, 0, 0, 0xff)
		sdl.RenderClear(render)

		drawText(titleText, (WIN_WIDTH - (i32(titleText.strLen) * (FONT_WIDTH * FONT_SIZE_MULT))) / 2, FONT_HEIGHT * FONT_SIZE_MULT)

		drawVoiceUi()

		if drawingWaveform {
			drawWaveform()
		}

		if drawingKeyboard {
			drawKeyboard()
		}

		sdl.RenderPresent(render)
		sdl.PumpEvents()
	}
}

updateUi :: proc() {
	if uiUpdateReady {
		for i in 0..<len(voices) {
			// add voice event?
			if len(voiceUI) < len(voices) {
				addVoiceUI()
			}

			for j in 0..<len(voices[i].waveforms) {
				// new waveform?
				if j >= len(voiceUI[i].waveforms) {
					addWaveformUI(i)
				}

				// waveform type change?
				if voiceUI[i].waveforms[j].wfType != voices[i].waveforms[j].type {
					voiceUI[i].waveforms[j].wfType = voices[i].waveforms[j].type

					switch voiceUI[i].waveforms[j].wfType {
						case .Sine:
							destroyText(voiceUI[i].waveforms[j].outputWfLabel)
							voiceUI[i].waveforms[j].outputWfLabel = newText("sin", COLOR_RED, COLOR_BLACK)
							return
						case .Sawtooth:
							destroyText(voiceUI[i].waveforms[j].outputWfLabel)
							voiceUI[i].waveforms[j].outputWfLabel = newText("saw", COLOR_RED, COLOR_BLACK)
							return
						case .Triangle:
							destroyText(voiceUI[i].waveforms[j].outputWfLabel)
							voiceUI[i].waveforms[j].outputWfLabel = newText("tri", COLOR_RED, COLOR_BLACK)
							return
						case .Square:
							destroyText(voiceUI[i].waveforms[j].outputWfLabel)
							voiceUI[i].waveforms[j].outputWfLabel = newText("sqr", COLOR_RED, COLOR_BLACK)
							return
					}
				} // amp change?
				else if voiceUI[i].waveforms[j].amp != voices[i].waveforms[j].amp {
					voiceUI[i].waveforms[j].amp = voices[i].waveforms[j].amp

					destroyText(voiceUI[i].waveforms[j].outputAmpLabel)
					voiceUI[i].waveforms[j].outputAmpLabel = newText((voiceUI[i].waveforms[j].amp < 0.05) ? "0.0" : fmt.caprintf("%.1f", voiceUI[i].waveforms[j].amp), COLOR_RED, COLOR_BLACK)
				} // freq proportion change?
				else if voiceUI[i].waveforms[j].freqProportionChanged {
					voiceUI[i].waveforms[j].freqProportionChanged = false
					destroyText(voiceUI[i].waveforms[j].outputFreqLabel)
					voiceUI[i].waveforms[j].outputFreqLabel = newText(fmt.caprintf("%.2f", voiceUI[i].waveforms[j].freqProportion), COLOR_RED, COLOR_BLACK)
				}
			}
		}

		uiUpdateReady = false
	}
}

// INPUT HANDLERS //

// returns index of keyboard key on true, -1 on false
isKeyboardKeyEvent :: proc(keycode: sdl.Keycode) -> i32 {
	for i: i32 = 0; i < 13; i += 1 {
		if keycode == keyboardKeys[i] {
			return i
		}
	}

	return -1
}

keyboardKeyUpEvent :: proc(key: i32) {
	keyboardKeyData[key].down = false
	if keyboardKeyData[key].voice != -1 {
		// if a note was pressed but not being played due to the voice cap, play it!
		// else, stop playing this voice
		for i := len(keyboardKeyData) - 1; i >= 0; i -= 1 {
			if keyboardKeyData[i].down && keyboardKeyData[i].voice == -1 {
				keyboardKeyData[i].voice = keyboardKeyData[key].voice
				adjustVoiceFreqs(keyboardKeyData[key].voice, freqOf(f32(octave * 12 + i32(i))))
				break
			}
			else if i == 0 {
				voices[keyboardKeyData[key].voice].playing = false
			}
		}

		keyboardKeyData[key].voice = -1
	}
}

keyboardKeyDownEvent :: proc(key: i32) {
	if !keyboardKeyData[key].down {
		keyboardKeyData[key].down = true

		// get the next voice to play
		for i in 0..<len(voices) {
			if !voices[i].playing || i == len(voices) - 1 {
				// unassign voice from previous note (it is still pressed!!!)
				if i == len(voices) - 1 {
					for j in 0..<len(keyboardKeyData) {
						if keyboardKeyData[j].voice == i {
							keyboardKeyData[j].voice = -1
							break
						}
					}
				}

				keyboardKeyData[key].voice = i
				voices[i].playing = true
				adjustVoiceFreqs(i, freqOf(f32(octave * 12 + key)))

				break
			}
		}
	}
}

addVoiceEvent :: proc() {
	if len(voices) < MAX_VOICES {
		waveforms := make([dynamic]VoiceWaveform)
		append(&waveforms, VoiceWaveform{Waveform.Sine, freqOf(12), 1.0, 0.0})
		addVoice(waveforms, 0)
		uiUpdateReady = true
	}
}

checkWaveformChangeEvent :: proc() -> bool {
	for i in 0..<len(voiceUI) {
		// add waveform
		if isMouseInsideButton(voiceUI[i].addWaveformButton) && len(voices[i].waveforms) < MAX_WAVEFORMS {
			append(&voices[i].waveforms, VoiceWaveform{Waveform.Sine, voices[i].waveforms[0].freq, 1.0, 0.0})
			uiUpdateReady = true
			return true
		}

		for j in 0..<len(voiceUI[i].waveforms) {
			// i must have been tweakin
			wf := voiceUI[i].waveforms[j]

			// wf change
			if isMouseInsideButton(wf.wfLeftButton) && voices[i].waveforms[j].type != Waveform.Sine {
				voices[i].waveforms[j].type -= Waveform(1)
				uiUpdateReady = true
				return true
			}
			else if isMouseInsideButton(wf.wfRightButton) && voices[i].waveforms[j].type != Waveform.Square {
				voices[i].waveforms[j].type += Waveform(1)
				uiUpdateReady = true
				return true
			} // amp change
			else if isMouseInsideButton(wf.ampLeftButton) && voices[i].waveforms[j].amp > 0.0 {
				voices[i].waveforms[j].amp -= 0.1
				uiUpdateReady = true
				return true
			}
			else if isMouseInsideButton(wf.ampRightButton) && voices[i].waveforms[j].amp < 1.0 {
				voices[i].waveforms[j].amp += 0.1
				uiUpdateReady = true
				return true
			} // freq proportion change
			else if isMouseInsideButton(wf.freqLeftButton) && wf.freqProportion > -9.0 && j != 0 {
				voiceUI[i].waveforms[j].freqProportionChanged = true
				voiceUI[i].waveforms[j].freqProportion -= 1.0 / 12.0
				uiUpdateReady = true

				adjustedNoteIndex: f32 = math.log2_f32(voices[i].waveforms[0].freq / BASE_FREQ) + voiceUI[i].waveforms[j].freqProportion
				voices[i].waveforms[j].freq = freqOf(adjustedNoteIndex * 12.0)
			}
			else if isMouseInsideButton(wf.freqRightButton) && wf.freqProportion < 9.0 && j != 0 {
				voiceUI[i].waveforms[j].freqProportionChanged = true
				voiceUI[i].waveforms[j].freqProportion += 1.0 / 12.0

				adjustedNoteIndex: f32 = math.log2_f32(voices[i].waveforms[0].freq / BASE_FREQ) + voiceUI[i].waveforms[j].freqProportion
				voices[i].waveforms[j].freq = freqOf(adjustedNoteIndex * 12.0)
				uiUpdateReady = true
			}
		}

	}

	return false
}

// hub input function, runs in its own thread
handleInput :: proc(_: ^thread.Thread) {
	for running {
		for sdl.WaitEvent(&event) {
			if event.type == sdl.EventType.QUIT {
				running = false
				return
			}
			else if event.type == sdl.EventType.KEYUP {
				// toggle audio device
				if event.key.keysym.sym == sdl.Keycode.p {
					sdl.PauseAudioDevice(audioDevice, !paused)
					paused = !paused
				} // toggle onscreen keyboard
				else if event.key.keysym.sym == sdl.Keycode.SPACE {
					drawingKeyboard = !drawingKeyboard
				} // toggle waveform output ui
				else if event.key.keysym.sym == sdl.Keycode.RETURN {
					drawingWaveform = !drawingWaveform
				} // octave changes
				else if event.key.keysym.sym == sdl.Keycode.UP {
					if octave < OCTAVE_MAX {
						octave += 1
					}
}
				else if event.key.keysym.sym == sdl.Keycode.DOWN {
					if octave > OCTAVE_MIN {
						octave -= 1
					}
				}
				else { // keyboard key release
					key := isKeyboardKeyEvent(event.key.keysym.sym)

					if key != -1 {
						keyboardKeyUpEvent(key)	
					}
				}
			} // keyboard key press
			else if event.type == sdl.EventType.KEYDOWN {
				key := isKeyboardKeyEvent(event.key.keysym.sym)

				if key != -1 {
					keyboardKeyDownEvent(key)
				}
			}
			else if event.type == sdl.EventType.MOUSEBUTTONUP {
				// add voice
				if isMouseInsideButton(addVoiceButton) {
					addVoiceEvent()
				}
				else {
					checkWaveformChangeEvent()
				}
			}
		}
	}
}
