{.experimental.}

import math
import soundio

type
  ResultKind = enum Ok, Err
  Result[T] = object
    case kind: ResultKind
    of Ok: value: T
    of Err: msg: string

# ---

proc writeCallback(outStream: ptr SoundIoOutStream, frameCountMin: cint, frameCountMax: cint) {.cdecl.} =
  let csz = sizeof SoundIoChannelArea
  let fsz = sizeof float32
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
        var ptrSample = cast[ptr float32](cast[int](ptrArea.pointer) + frame*fsz)
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

proc sserr(msg: string): Result[SoundSystem] =
  return Result[SoundSystem](kind: Err, msg: msg)

proc newSoundSystem(): Result[SoundSystem] =
  let sio = soundioCreate()
  if sio.isNil:
    return sserr "out of mem"

  var err = sio.connect
  if err > 0:
    return sserr "Unable to connect to backend: " & $err.strerror

  echo "Backend: \t", sio.currentBackend.name
  sio.flushEvents

  let devID = sio.defaultOutputDeviceIndex
  if devID < 0:
    return sserr "Output device is not found"
  let device = sio.getOutputDevice(devID)
  if device.isNil:
    return sserr "out of mem"
  if device.probeError > 0:
    return sserr "Cannot probe device"

  echo "Output device:\t", device.name

  return Result[SoundSystem](
    kind: Ok,
    value: SoundSystem(sio: sio, device: device))

# ---

type
  OutStream = object
    stream: ptr SoundIoOutStream
    userdata: pointer

proc `=destroy`(s: var OutStream) =
  s.stream.destroy
  dealloc(s.userdata)

proc oserr(msg: string): Result[OutStream] =
  return Result[OutStream](kind: Err, msg: msg)

proc newOutStream(ss: SoundSystem): Result[OutStream] =
  let stream = ss.device.outStreamCreate
  stream.write_callback = writeCallback
  var phase = alloc(sizeof(float64))
  stream.userdata = phase

  var err = stream.open
  if err > 0:
    return oserr "Unable to open device: " & $err.strerror

  if stream.layoutError > 0:
    return oserr "Unable to set channel layout: " & $stream.layoutError.strerror

  err = stream.start
  if err > 0:
    return oserr "Unable to start stream: " & $err.strerror

  return Result[OutStream](value: OutStream(stream: stream, userdata: phase))

# ---

let rss = newSoundSystem()
if rss.kind == Err:
  quit rss.msg
let ss = rss.value

let ros = newOutStream(ss)
if ros.kind == Err:
  quit ros.msg
let outstream = ros.value.stream

echo "Format:\t\t", outstream.format
echo "Sample Rate:\t", outstream.sampleRate
echo "Latency:\t", outstream.softwareLatency

while true:
  ss.sio.flushEvents
  let s = stdin.readLine
  if s == "quit":
    break
