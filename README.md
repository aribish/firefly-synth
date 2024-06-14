# firefly-synth
An additive synthesizer using Odin and SDL2. IN DEVELOPMENT

![Sun Jun  9 10:07:57 AM EDT 2024](https://github.com/aribish/firefly-synth/assets/67713226/7f0e67d1-7c89-4ac3-b2e2-1a80f8af1ca7)

## 2024-06-13
Pretty big update, but I am uploading it only partially finished just to back it up real quick

I'm very close to finishing the UI for the main part of the synth, before I start the backend for
filters and effects. I've messed around with a couple UI arrangements, and working around my self-imposed
restrictions of making this look all retro has been pretty hard.

Here's how the waveform UI is setup:
* `WF <>` - click the arrows to choose between 4 basic waveforms
* `A <>` - changes the amplitude of the waveform
* `F <>` - increases/decreases the semitone offset from the root waveform. It is displayed as the offset divided by 12 right now, I'll change that later

## 2024-06-09
Here is a demo of what I've done so far! Below is a list of features:
* Keyboard input (No MIDI yet)
* Output waveform and keyboard input UI
* Polyphony!!!
* Four basic waveforms that can be combined (No UI or effects yet)
  - You can control the frequency and amplitude of each waveform within each voice
  - So for example, you can combine sine waves at different places in the harmonic series to naturally form a sawtooth wave
  - Or you can play chords using just one voice!
