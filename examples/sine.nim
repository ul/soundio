import math
import soundio

proc writeCallback(outStream: ptr SoundIoOutStream, frameCountMin: cint, frameCountMax: cint) {.cdecl.} =
  let csz = sizeof SoundIoChannelArea
  let deltaPhase = 1.0/outStream.sampleRate.toFloat
  var areas: ptr SoundIoChannelArea
  var phase = cast[ptr float64](outStream.userdata)
  var framesLeft = frameCountMax
  var err: cint
  while true:
    var frameCount = framesLeft
    err = outStream.beginWrite(areas.addr, frameCount.addr)
    if err > 0:
      quit "Unrecoverable stream error: " & $err.strerror
    if frameCount <= 0:
      break
    let layout = outstream.layout
    let ptrAreas = cast[int](areas)
    for frame in 0..<frameCount:
      let sample = sin 440.0*2.0*PI*phase[]
      phase[] += deltaPhase
      for channel in 0..<layout.channelCount:
        let ptrArea = cast[ptr SoundIoChannelArea](ptrAreas + channel*csz)
        var ptrSample = cast[ptr float32](cast[int](ptrArea.pointer) + frame*ptrArea.step)
        ptrSample[] = sample
    err = outstream.endWrite
    if err > 0 and err != cint(SoundIoError.Underflow):
      quit "Unrecoverable stream error: " & $err.strerror
    framesLeft -= frameCount
    if framesLeft <= 0:
      break

# ---

type
  SoundSystem = object
    sio: ptr SoundIo
    device: ptr SoundIoDevice

proc `=destroy`(s: var SoundSystem) =
  s.device.unref
  s.sio.destroy

proc newSoundSystem(): SoundSystem =
  let sio = soundioCreate()
  if sio.isNil:
    quit "out of mem"

  var err = sio.connect
  if err > 0:
    quit "Unable to connect to backend: " & $err.strerror

  echo "Backend: \t", sio.currentBackend.name
  sio.flushEvents

  let devID = sio.defaultOutputDeviceIndex
  if devID < 0:
    quit "Output device is not found"
  let device = sio.getOutputDevice(devID)
  if device.isNil:
    quit "out of mem"
  if device.probeError > 0:
    quit "Cannot probe device"

  echo "Output device:\t", device.name

  return SoundSystem(sio: sio, device: device)

# ---

type
  OutStream = object
    stream: ptr SoundIoOutStream
    userdata: pointer

proc `=destroy`(s: var OutStream) =
  s.stream.destroy
  dealloc(s.userdata)

proc newOutStream(ss: SoundSystem): OutStream =
  let stream = ss.device.outStreamCreate
  stream.write_callback = writeCallback
  var phase = alloc(sizeof(float64))
  stream.userdata = phase

  var err = stream.open
  if err > 0:
    quit "Unable to open device: " & $err.strerror

  if stream.layoutError > 0:
    quit "Unable to set channel layout: " & $stream.layoutError.strerror

  err = stream.start
  if err > 0:
    quit "Unable to start stream: " & $err.strerror

  return OutStream(stream: stream, userdata: phase)

# ---

let ss = newSoundSystem()
let outstream = newOutStream(ss).stream

echo "Format:\t\t", outstream.format
echo "Sample Rate:\t", outstream.sampleRate
echo "Latency:\t", outstream.softwareLatency

while true:
  ss.sio.flushEvents
  let s = stdin.readLine
  if s == "quit":
    break
