# Music & DAW Basics

This page is for users who have never used music software. We'll cover some basic vocabulary and concepts. Nothing on this page is Porydaw-specific--these are general concepts.

## What's a DAW, anyway?

A "Digital Audio Workstation" is a program for arranging music notes and sounds on a timeline. Porydaw is a small, specialized one. DAWs are notoriously complex pieces of software because they are incredibly feature-rich and powerful. In short, DAWs are the ultimate tool for creating music. They are used by anyone from professionals creating top-40 pop hits to hobbyists creating songs for their GBA ROM hacks.  Some examples of popular DAWs are [Pro Tools](https://www.avid.com/pro-tools), [Logic Pro](https://www.apple.com/logic-pro/), [Ableton Lilve](https://www.ableton.com/en/live/), [FL Studio](https://www.image-line.com/), and [Reaper](https://www.reaper.fm/).


## Notes, pitch, and the piano roll

In audio, "pitch" is the frequency of a sound--how high or low it sounds. "Keys" refers to certain pitches--e.g. the keys on a piano. A "note" is a combination of a key and duration.  In music software, a song's notes are often laid out in a 2D "piano roll", where the horizontal axis represents time and vertical axis represents keys.  And so, notes appear as horizontal bars in that piano roll timeline.

## Rhythm: beats, bars, and tempo

How fast or slow a song progresses through the timeline is determined by the "tempo". Tempo is measured in "beats per minute", and a "beat" is the thing you tap your foot to while listening to music.  To logically group sections of the music together, music is typically organized into "measures, each of which is subdivided even further into "beats" and sub-beats. These concepts appear as vertical lines in the piano roll view and are how music is organized horizontally over time.

## Tracks and instruments

Songs can be composed of multiple "tracks". A track is a logical "voice" producing sound. For example, if a song has a male singer and a guitar playing, there would be two separate tracks--one for the singer and one for the guitar. Tracks exist independently, and their sounds are added together to produce the final audio.

## Velocity and dynamics

One of the most basic methods of adding musicality is to use different loudness for different notes and instruments. The loudness of a note can be controlled in a few ways:
1. The individual note's "velocity". Each note can specify how soft or loud it should play.
2. The overall track's Volume setting.
3. The overall song's Volume setting.

These three are combined to determine how loud a note is when the final audio is played.

## Things that make GBA music special

Unlike typical DAWs which have effectively limitless audio capabilities, Porydaw is restricted by what the GBA and m4a music engine can do.

The GBA can only play a handful of sounds at once, and there are two families of sounds that it can produce: (1) arbitrary sampled instruments, and (2) built-in "chiptune" channels (square/wave/noise).  See [Polyphony & GBA Sound Limits](../manual/polyphony.md) for more details.
