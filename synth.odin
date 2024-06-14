package main

import "core:fmt"
import "core:math"
import "core:runtime"
import "core:thread"
import sdl "vendor:sdl2"

SAMPLE_RATE :: 44100
SAMPLES_PER_BUFFER :: 1024
BASE_FREQ :: 16.351

Waveform :: enum {
	Sine,
	Sawtooth,
	Triangle,
	Square
}

VoiceWaveform :: struct {
	type: Waveform,
	freq: f32,
	amp: f32,
	phase: f32
}

VoiceData :: struct {
	waveforms: [dynamic]VoiceWaveform,
	semitoneOffset: f32, 	// i dont even remember why this is here
							// or what it does if even anything bruh
	playing: bool
}

audioDevice: sdl.AudioDeviceID
audioSpec: sdl.AudioSpec
paused := true

voices: [dynamic]VoiceData

buffer: [^]f32
audioThread: ^thread.Thread
started := false

initSynth :: proc() {
	desiredAudioSpec: sdl.AudioSpec
	desiredAudioSpec.freq = SAMPLE_RATE
	desiredAudioSpec.format = sdl.AUDIO_F32
	desiredAudioSpec.channels = 1
	desiredAudioSpec.samples = SAMPLES_PER_BUFFER
	desiredAudioSpec.callback = nil
	desiredAudioSpec.userdata = nil

	audioDevice = sdl.OpenAudioDevice(nil, false, &desiredAudioSpec, &audioSpec, {})
	buffer = make([^]f32, SAMPLES_PER_BUFFER)
	started = true
	audioThread = thread.create(fillBuffer)
	audioThread.init_context = context
	audioThread.user_index = 1
	thread.start(audioThread)
}

quitSynth :: proc() {
	started = false
	sdl.CloseAudioDevice(audioDevice)
	
	for i in 0..<len(voices) {
		delete(voices[i].waveforms)
	}
	delete(voices)
	free(buffer)

	thread.destroy(audioThread)
}

freqOf :: proc(note: f32) -> f32 {
	return BASE_FREQ * math.pow_f32(2.0, (note / 12.0))
}
addVoice :: proc(waveforms: [dynamic]VoiceWaveform, freqOffset: f32) {
	append(&voices, VoiceData{waveforms, freqOffset, false})
}

fillBuffer :: proc(_: ^thread.Thread) {
	// i am so sorry about this :,(
	for started {
		if sdl.GetQueuedAudioSize(audioDevice) > SAMPLES_PER_BUFFER * 4 {
			continue
		}

		for i in 0..<SAMPLES_PER_BUFFER {
			buffer[i] = 0.0
		}
	
		for i in 0..<len(voices) {
			voice := voices[i]

			if !voice.playing {
				continue
			}

			for j in 0..<len(voice.waveforms) {
				cycle := (1.0 / voice.waveforms[j].freq) * SAMPLE_RATE
				for k in 0..<SAMPLES_PER_BUFFER {
					switch voice.waveforms[j].type {
						case .Sine:
						buffer[k] += math.sin(math.PI * 2.0 * voice.waveforms[j].phase) * voice.waveforms[j].amp
						break

						case.Sawtooth:
						buffer[k] += (-1.0 + 2.0 * (voice.waveforms[j].phase)) * voice.waveforms[j].amp
						break
						
						case.Square:
						buffer[k] += ((voice.waveforms[j].phase < 0.5) ? 1.0 : -1.0) * voice.waveforms[j].amp
						break

						case.Triangle:
						buffer[k] += ((voice.waveforms[j].phase < 0.5) ? voice.waveforms[j].phase * 4.0 - 1.0 : (voice.waveforms[j].phase - 0.5) * -4.0 + 1.0) * voice.waveforms[j].amp
						break
					}

					voice.waveforms[j].phase += 1.0 / cycle
					if voice.waveforms[j].phase >= 1.0 {
						voice.waveforms[j].phase -= 1.0
					}

					if buffer[k] > 1.0 {
						buffer[k] = 1.0
					}
					else if buffer[k] < -1.0 {
						buffer[k] = -1.0
					}
				}
			}
		}

		sdl.QueueAudio(audioDevice, buffer, SAMPLES_PER_BUFFER * 4)
	}
}

adjustVoiceFreqs :: proc(voiceIndex: int, rootFreq: f32) {
	offset := math.log2_f32(rootFreq / BASE_FREQ) - math.log2_f32(voices[voiceIndex].waveforms[0].freq / BASE_FREQ)

	for i in 0..<len(voices[voiceIndex].waveforms) {
		power := math.log2_f32(voices[voiceIndex].waveforms[i].freq / BASE_FREQ)
		voices[voiceIndex].waveforms[i].freq = BASE_FREQ * math.pow_f32(2, power + offset)
	}
}
