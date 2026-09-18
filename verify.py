#!/usr/bin/env python3
"""Smoke-test a native release artifact before publishing it."""
import ctypes as c
import pathlib
import sys


class Error(c.Structure):
    _fields_ = [("code", c.c_int), ("subcode", c.c_int), ("message", c.c_char_p)]


def check(error):
    if error.code:
        raise RuntimeError(error.message.decode("utf-8", errors="replace"))


artifact, fixture = map(pathlib.Path, sys.argv[1:])
lib = c.CDLL(str(artifact.resolve()))
lib.heif_get_version_number.restype = c.c_uint32
assert lib.heif_get_version_number() == 0x01170400, "expected libheif 1.23.4"
lib.heif_have_decoder_for_format.argtypes = [c.c_int]
lib.heif_init.argtypes = [c.c_void_p]
lib.heif_init.restype = Error
lib.heif_deinit.restype = None
lib.heif_context_alloc.restype = c.c_void_p
lib.heif_context_free.argtypes = [c.c_void_p]
lib.heif_context_free.restype = None
lib.heif_context_read_from_file.argtypes = [c.c_void_p, c.c_char_p, c.c_void_p]
lib.heif_context_read_from_file.restype = Error
lib.heif_context_get_primary_image_handle.argtypes = [c.c_void_p, c.POINTER(c.c_void_p)]
lib.heif_context_get_primary_image_handle.restype = Error
lib.heif_image_handle_release.argtypes = [c.c_void_p]
lib.heif_image_handle_release.restype = None
lib.heif_decode_image.argtypes = [c.c_void_p, c.POINTER(c.c_void_p), c.c_int, c.c_int, c.c_void_p]
lib.heif_decode_image.restype = Error
lib.heif_image_release.argtypes = [c.c_void_p]
lib.heif_image_release.restype = None

check(lib.heif_init(None))
try:
    assert lib.heif_have_decoder_for_format(1), "HEVC decoder missing"
    ctx = lib.heif_context_alloc()
    assert ctx, "context allocation failed"
    try:
        check(lib.heif_context_read_from_file(ctx, str(fixture.resolve()).encode(), None))
        handle = c.c_void_p()
        check(lib.heif_context_get_primary_image_handle(ctx, c.byref(handle)))
        try:
            image = c.c_void_p()
            check(lib.heif_decode_image(handle, c.byref(image), 1, 11, None))
            lib.heif_image_release(image)
        finally:
            lib.heif_image_handle_release(handle)
    finally:
        lib.heif_context_free(ctx)
finally:
    lib.heif_deinit()
print(f"Verified {artifact.name}: libheif 1.23.4, HEVC decode passed")
