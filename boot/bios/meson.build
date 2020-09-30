assemble = generator(find_program('nasm'),
    output : '@BASENAME@.o',
    arguments : [ '-felf64', '@INPUT@', '-o', '@OUTPUT@' ]
)

src += [
    assemble.process('boot.asm'),
    'boot.c'
]

ldscript = meson.current_source_dir()/'link.ld'

kernel = executable('bezos.bin', src,
    link_args : [ '-Wl,-T' + ldscript ],
    link_depends : ldscript,
    include_directories : inc
)