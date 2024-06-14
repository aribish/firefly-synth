package main

import sdl "vendor:sdl2"
import "vendor:sdl2/ttf"
import "core:fmt"

COLOR_RED :: sdl.Color{0xff, 0, 0, 0xff}
COLOR_YELLOW :: sdl.Color{0xff, 0xff, 0, 0xff}
COLOR_BLACK :: sdl.Color{0, 0, 0, 0xff}

Text :: struct {
	texture: ^sdl.Texture,
	strLen: int
}

Button :: struct {
	x, y, w, h: i32,
	text: Text, // if texture is null, text and fg is not used
	border: bool, // if false, borderColor is not used
	fg, bg, borderColor: sdl.Color
}

WaveformUI :: struct {
	wfLabel: Text,
	wfLeftButton, wfRightButton: Button,
	outputWfLabel: Text,
	wfType: Waveform,
	
	ampLabel: Text,
	ampLeftButton, ampRightButton: Button,
	outputAmpLabel: Text,
	amp: f32,

	freqLabel: Text,
	freqLeftButton, freqRightButton: Button,
	outputFreqLabel: Text,
	freqProportion: f32,
	// the type change variable is there because there is no way to tell if this change
	// ocurred just by the comparing saved ui data to the actual waveform data
	freqProportionChanged: bool
}

VoiceUI :: struct {
	header: Text,
	waveforms: [dynamic]WaveformUI,
	addWaveformButton: Button
}

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

voiceUI: [dynamic]VoiceUI
addVoiceButton: Button

newText :: proc(text: cstring, fg, bg: sdl.Color) -> Text {
	texture: ^sdl.Texture = nil

	if text == nil {
		return Text {
			nil,
			0
		}
	}

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

// NOTE All text is expected to be one line
drawText :: proc(text: Text, x, y: i32) {
	rect := sdl.Rect {
		x, y,
		i32(text.strLen) * FONT_WIDTH, FONT_HEIGHT * FONT_SIZE_MULT
	}
	sdl.RenderCopy(render, text.texture, nil, &rect)
}

destroyText :: proc(text: Text) {
	sdl.DestroyTexture(text.texture)
}

newButton :: proc(x, y, w, h: i32, text: cstring, border: bool, fg, bg, borderColor: sdl.Color) -> Button {
	return Button {
		x, y, w, h,
		newText(text, fg, bg),
		border,
		fg, bg, borderColor
	}
}

drawButton :: proc(button: Button) {
	sdl.SetRenderDrawColor(render, button.bg.r, button.bg.g, button.bg.b, button.bg.a)
	sdl.RenderDrawRect(render, &sdl.Rect{button.x, button.y, button.w, button.h})
	if button.text.texture != nil {
		drawText(button.text, button.x + (button.w - i32(button.text.strLen) * FONT_WIDTH * FONT_SIZE_MULT) / 2, button.y + (button.h - FONT_HEIGHT * FONT_SIZE_MULT) / 2)
	}

	if button.border {
		sdl.SetRenderDrawColor(render, button.borderColor.r, button.borderColor.g, button.borderColor.b, button.borderColor.a)
		sdl.RenderDrawRect(render, &sdl.Rect{button.x, button.y, button.w, button.h})
	}
}

isMouseInsideButton :: proc(button: Button) -> bool {
	x, y: i32
	sdl.GetMouseState(&x, &y)

	if x >= button.x && x <= button.x + button.w &&
	y >= button.y && y <= button.y + button.h {
		return true
	}

	return false
}

destroyButton :: proc(button: Button) {
	sdl.DestroyTexture(button.text.texture)
}

initGui :: proc() {
	ttf.Init()
	font = ttf.OpenFont("PeaberryMono.ttf", FONT_HEIGHT * FONT_SIZE_MULT)
	
	voicesHeaderText = newText("Output Waveform", COLOR_BLACK, COLOR_YELLOW)
	
	addVoiceButton = newButton(FONT_WIDTH * FONT_SIZE_MULT,
	FONT_HEIGHT * FONT_SIZE_MULT * 3,
	FONT_WIDTH * FONT_SIZE_MULT * len("New Voice"),
	FONT_HEIGHT * FONT_SIZE_MULT,
	"New Voice", true, COLOR_YELLOW, COLOR_BLACK, COLOR_YELLOW)
}

quitGui :: proc() {
	for ui in voiceUI {
		destroyText(ui.header)
		for wf in ui.waveforms {
			destroyText(wf.wfLabel)
			destroyText(wf.outputWfLabel)
			destroyButton(wf.wfLeftButton)
			destroyButton(wf.wfRightButton)
		}
	}
	destroyButton(addVoiceButton)
	ttf.CloseFont(font)
	ttf.Quit()
}

drawWaveform :: proc() {
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
}

drawKeyboard :: proc() {
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
}

// NOTE and TODO fuck
// for some reason new ui IS being made, and input IS being recognized,
// but shit isn't like drawing right or something
// it could be because of shit with input being in its own thread???

addVoiceUI :: proc() {
	// just to be careful ig
	if len(voiceUI) < len(voices) {
		newUI: VoiceUI
		newUI.header = newText(fmt.caprintf("Voice {}", len(voiceUI)), COLOR_YELLOW, COLOR_BLACK)

		append(&voiceUI, newUI)
		addVoiceButton.x += 8 * FONT_WIDTH * FONT_SIZE_MULT
	}
}

addWaveformUI :: proc(voice: int) {
	if len(voiceUI[voice].waveforms) < len(voices[voice].waveforms) {
		x := i32(voice * 8 + 1) * FONT_WIDTH * FONT_SIZE_MULT
		y: i32 = (4 + i32(len(voiceUI[voice].waveforms)) * 4) * FONT_HEIGHT * FONT_SIZE_MULT // NOTE 1 will be replaced by total height of the shit

		newUI: WaveformUI
		newUI.wfLabel = newText("WF", COLOR_YELLOW, COLOR_BLACK)
		newUI.wfLeftButton = newButton(x + FONT_WIDTH * FONT_SIZE_MULT * 2, y, FONT_WIDTH * FONT_SIZE_MULT, FONT_HEIGHT * FONT_SIZE_MULT, "<", false, COLOR_BLACK, COLOR_YELLOW, COLOR_BLACK)
		newUI.wfRightButton = newButton(x + FONT_WIDTH * FONT_SIZE_MULT * 3, y, FONT_WIDTH * FONT_SIZE_MULT, FONT_HEIGHT * FONT_SIZE_MULT, ">", false, COLOR_BLACK, COLOR_YELLOW, COLOR_BLACK)
		newUI.wfType = Waveform.Sine
		newUI.outputWfLabel = newText("sin", COLOR_RED, COLOR_BLACK)

		y += FONT_HEIGHT * FONT_SIZE_MULT
		newUI.ampLabel = newText("A", COLOR_YELLOW, COLOR_BLACK)
		newUI.ampLeftButton = newButton(x + FONT_WIDTH * FONT_SIZE_MULT * 2, y, FONT_WIDTH * FONT_SIZE_MULT, FONT_HEIGHT * FONT_SIZE_MULT, "<", false, COLOR_BLACK, COLOR_YELLOW, COLOR_BLACK)
		newUI.ampRightButton = newButton(x + FONT_WIDTH * FONT_SIZE_MULT * 3, y, FONT_WIDTH * FONT_SIZE_MULT, FONT_HEIGHT * FONT_SIZE_MULT, ">", false, COLOR_BLACK, COLOR_YELLOW, COLOR_BLACK)
		newUI.outputAmpLabel = newText("1.0", COLOR_RED, COLOR_BLACK)
		newUI.amp = 1.0

		y += FONT_HEIGHT * FONT_SIZE_MULT
		newUI.freqLabel = newText("F", COLOR_YELLOW, COLOR_BLACK)
		newUI.freqLeftButton = newButton(x + FONT_WIDTH * FONT_SIZE_MULT, y, FONT_WIDTH * FONT_SIZE_MULT, FONT_HEIGHT * FONT_SIZE_MULT, "<", false, COLOR_BLACK, COLOR_YELLOW, COLOR_BLACK)
		newUI.freqRightButton = newButton(x + FONT_WIDTH * FONT_SIZE_MULT * 2, y, FONT_WIDTH * FONT_SIZE_MULT, FONT_HEIGHT * FONT_SIZE_MULT, ">", false, COLOR_BLACK, COLOR_YELLOW, COLOR_BLACK)

		newUI.outputFreqLabel = newText("-0.0", COLOR_RED, COLOR_BLACK)
		newUI.freqProportion = 0.0

		y += FONT_HEIGHT * FONT_SIZE_MULT
		destroyButton(voiceUI[voice].addWaveformButton)
		voiceUI[voice].addWaveformButton = newButton(x, y, FONT_WIDTH * FONT_SIZE_MULT * 7, FONT_HEIGHT * FONT_SIZE_MULT, "Add WF", true, COLOR_YELLOW, COLOR_BLACK, COLOR_YELLOW)

		append(&voiceUI[voice].waveforms, newUI)
	}
}

// NOTE new ui elements will be created as needed inside this function!!!
// i regret this very much
drawVoiceUi :: proc() {
	// draw voice headers
	for i in 0..<len(voiceUI) {
		x := i32(i * 8 + 1) * FONT_WIDTH * FONT_SIZE_MULT
		drawText(voiceUI[i].header, x, FONT_HEIGHT * FONT_SIZE_MULT * 3)

		// waveform ui
		for j in 0..<len(voiceUI[i].waveforms) {
			y: i32 = (4 + i32(j) * 4) * FONT_HEIGHT * FONT_SIZE_MULT // NOTE 1 will be replaced by total height of the shit
			
			// draw waveform ui
			wf := voiceUI[i].waveforms[j]
			drawText(wf.wfLabel, x, y)
			drawButton(wf.wfLeftButton)
			drawButton(wf.wfRightButton)
			drawText(wf.outputWfLabel, x + FONT_WIDTH * FONT_SIZE_MULT * 4, y)

			y += FONT_HEIGHT * FONT_SIZE_MULT
			drawText(wf.ampLabel, x, y)
			drawButton(wf.ampLeftButton)
			drawButton(wf.ampRightButton)
			drawText(wf.outputAmpLabel, x + FONT_WIDTH * FONT_SIZE_MULT * 4, y)

			y += FONT_HEIGHT * FONT_SIZE_MULT
			drawText(wf.freqLabel, x, y)
			drawButton(wf.freqLeftButton)
			drawButton(wf.freqRightButton)
			drawText(wf.outputFreqLabel, x + FONT_WIDTH * FONT_SIZE_MULT * ((wf.freqProportion <= 0.0) ? 3 : 4), y)

			drawButton(voiceUI[i].addWaveformButton)
		}
	}

	if len(voices) < MAX_VOICES {
		drawButton(addVoiceButton)
	}
}
