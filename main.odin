package main

import "core:fmt"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"
import "core:c"
import "core:thread"

WIN_WIDTH :: 800
WIN_HEIGHT :: 600
FPS :: 30

FONT_WIDTH :: 14
FONT_HEIGHT :: 16
FONT_SIZE_MULT :: 1

OCTAVE_MIN :: 1
OCTAVE_MAX :: 7

Text :: struct {
	texture: ^sdl.Texture,
	strLen: int
}

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

whiteKeys: [8]i32 = { // for ui
	0,
	2,
	4,
	5,
	7,
	9,
	11,
	12
}
blackKeys: [5]i32 = { // for ui
	1,
	3,
	6,
	8,
	10
}

octave: i32 = 4
keyboardKeysDown: []i32 // pressed key for each voice

// returns index of keyboard key on true, -1 on false
isKeyboardKeyEvent :: proc(keycode: sdl.Keycode) -> i32 {
	for i: i32 = 0; i < 13; i += 1 {
		if keycode == keyboardKeys[i] {
			return i
		}
	}

	return -1
}

handleInput :: proc(_: ^thread.Thread) {
	for running {
		for sdl.WaitEvent(&event) {
			if event.type == sdl.EventType.QUIT {
				running = false
				return
			}
			else if event.type == sdl.EventType.KEYUP {
				if event.key.keysym.sym == sdl.Keycode.SPACE {
					sdl.PauseAudioDevice(audioDevice, !paused)
					paused = !paused
				}
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
				else {
					key := isKeyboardKeyEvent(event.key.keysym.sym)

					if key != -1 {
						keyboardKeyData[key].down = false

						if keyboardKeyData[key].voice != -1 {
							// if a note was pressed but not being played due to the voice cap, play it!
							// else, stop playing this voice
							for i in 0..<len(keyboardKeyData) {
								if keyboardKeyData[i].down && keyboardKeyData[i].voice == -1 {
									keyboardKeyData[i].voice = keyboardKeyData[key].voice
									adjustVoiceFreqs(keyboardKeyData[key].voice, freqOf(f32(octave * 12 + i32(i))))
									break
								}
								else if i == len(keyboardKeyData) - 1 {
									voices[keyboardKeyData[key].voice].playing = false
								}
							}

							keyboardKeyData[key].voice = -1
						}
					}
				}
			}
			else if event.type == sdl.EventType.KEYDOWN {
				key := isKeyboardKeyEvent(event.key.keysym.sym)

				if key != -1 && !keyboardKeyData[key].down {
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
		}
	}
}

generateText :: proc(text: cstring, fg, bg: sdl.Color) -> Text {
	texture: ^sdl.Texture = nil

	surface: ^sdl.Surface = ttf.RenderText_Shaded(font, text, fg, bg)
	if surface != nil {
		texture = sdl.CreateTextureFromSurface(render, surface)
		sdl.FreeSurface(surface)
	}

	return Text {
		texture,
		len(text)
	}
}

// NOTE All text is expected to be 
drawText :: proc(text: Text, x, y: i32) {
	rect := sdl.Rect {
		x, y,
		i32(text.strLen) * FONT_WIDTH, FONT_HEIGHT * FONT_SIZE_MULT
	}
	sdl.RenderCopy(render, text.texture, nil, &rect)
}

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

	// init text
	ttf.Init()
	defer ttf.Quit()

	font = ttf.OpenFont("PeaberryMono.ttf", FONT_HEIGHT * FONT_SIZE_MULT)
	defer ttf.CloseFont(font)
	
	titleText = generateText("Odin Synthesizer", sdl.Color{0, 0, 0, 0xff}, sdl.Color{0xff, 0xff, 0, 0xff})
	defer sdl.DestroyTexture(titleText.texture)

	voicesHeaderText = generateText("Output Waveform", sdl.Color{0, 0, 0, 0xff}, sdl.Color{0xff, 0xff, 0, 0xff})
	defer sdl.DestroyTexture(voicesHeaderText.texture)


	// init audio
	initSynth()
	defer quitSynth()
	sdl.PauseAudioDevice(audioDevice, false)

	// temp
	waveforms: [dynamic]VoiceWaveform
	defer delete(waveforms)
	append(&waveforms, VoiceWaveform{Waveform.Triangle, freqOf(48), 0.5, 0.0})
	append(&waveforms, VoiceWaveform{Waveform.Sawtooth, freqOf(24), 0.75, 0.0})
	append(&waveforms, VoiceWaveform{Waveform.Sine, freqOf(12), 1.0, 0.0})
	addVoice(waveforms, 0)
	addVoice(waveforms, 0)
	addVoice(waveforms, 0)
	addVoice(waveforms, 0)

	for running {
		tick := sdl.GetTicks()
		if tick >= nextTick {
			nextTick = tick + 1000 / FPS
		}
		else {
			continue
		}

		sdl.SetRenderDrawColor(render, 0, 0, 0, 0xff)
		sdl.RenderClear(render)

		drawText(titleText, (WIN_WIDTH - (i32(titleText.strLen) * (FONT_WIDTH * FONT_SIZE_MULT))) / 2, FONT_HEIGHT * FONT_SIZE_MULT)

		// draw waveforms
		drawText(voicesHeaderText, 0, WIN_HEIGHT - 100 - FONT_HEIGHT * FONT_SIZE_MULT)
		sdl.SetRenderDrawColor(render, 0xff, 0xff, 0, 0xff)
		sdl.RenderFillRect(render, &sdl.Rect{0, WIN_HEIGHT - 100, WIN_WIDTH, 100})

		sdl.SetRenderDrawColor(render, 0xff, 0, 0, 0xff)
		lastY: i32 = WIN_HEIGHT - 50 - i32(50.0 * buffer[0])
		inc: int = SAMPLES_PER_BUFFER / WIN_WIDTH
		for i := inc; i < WIN_WIDTH; i += inc {
			y: i32 = WIN_HEIGHT - 50 - i32(50.0 * buffer[i])
			sdl.RenderDrawLine(render, i32(i - 1), lastY, i32(i), y)
			lastY = y
		}


		// draw keyboard keys
		sdl.SetRenderDrawColor(render, 0xff, 0xff, 0, 0xff)
		sdl.RenderFillRect(render, &sdl.Rect{(WIN_WIDTH - 320) / 2, WIN_HEIGHT - 200 - FONT_HEIGHT * FONT_SIZE_MULT, 
			320, 100})

		for i in 0..<8 {
			rect := sdl.Rect {
				(WIN_WIDTH - 320) / 2 + i32(i) * 40,
				WIN_HEIGHT - 200 - FONT_HEIGHT * FONT_SIZE_MULT,
				40,
				100
			}

			sdl.SetRenderDrawColor(render, 0, 0, 0, 0xff)
			sdl.RenderDrawRect(render, &rect)
			if keyboardKeyData[whiteKeys[i]].voice != -1 {
				rect.x += 1
				rect.y += 1
				rect.w -= 2
				rect.h -= 2

				sdl.SetRenderDrawColor(render, 0xff, 0, 0, 0xff)
				sdl.RenderFillRect(render, &rect)
			}
		}

		for i in 0..<5 {
			

			rect := sdl.Rect {
				20 + (WIN_WIDTH - 320) / 2 + i32(i) * 40,
				WIN_HEIGHT - 200 - FONT_HEIGHT * FONT_SIZE_MULT,
				40,
				50
			}

			if i >= 2 {
				rect.x += 40
			}

			sdl.SetRenderDrawColor(render, 0, 0, 0, 0xff)
			sdl.RenderDrawRect(render, &rect)

			rect.x += 1
			rect.y += 1
			rect.w -= 2
			rect.h -= 2

			if keyboardKeyData[blackKeys[i]].voice == -1 {
				sdl.SetRenderDrawColor(render, 0xff, 0xff, 0, 0xff)
			}
			else {
				sdl.SetRenderDrawColor(render, 0xff, 0, 0, 0xff)
			}
			sdl.RenderFillRect(render, &rect)
		}

		sdl.RenderPresent(render)
		sdl.PumpEvents()
	}
}
