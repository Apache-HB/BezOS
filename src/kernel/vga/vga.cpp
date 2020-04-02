#include "vga.h"

#include "common/types.h"

#define VGA_WIDTH 80
#define VGA_HEIGHT 25
#define VGA_BUFFER ((uint16*)0xB8000)

#define VGA_COLOUR(fg, bg) (fg | bg << 4)
#define VGA_ENTRY(letter, colour) (letter | colour << 8)

static int vga_row;
static int vga_column;

namespace vga
{
    void init()
    {
        vga_row = 0;
        vga_column = 0;
    }

    static void put(char c)
    {
        if(c == '\n')
        {
            vga_row++;
            vga_column = 0;
            return;
        }
        
        if(vga_column == VGA_WIDTH)
        {
            vga_column = 0;
            
            if(++vga_row == VGA_HEIGHT)
            {
                vga_row = 0;
            }
        }

        VGA_BUFFER[vga_row * VGA_WIDTH + vga_column] = VGA_ENTRY(c, VGA_COLOUR(7, 0));

        vga_column++;
    }

    void putc(char c)
    {
        put(c);
    }

    void puts(const char* str)
    {
        while(*str)
            put(*str++);
    }

    void puti(int val, int base)
    {
        if(base == 16)
        {
            puts("0x");
        } 
        else if(base == 2)
        {
            puts("0b");
        }

        if(!val)
        {
            put('0');
            return;
        }
        
        char buf[32] = {0};

        int i = 30;

        for(; val && i; --i, val /= base)
            buf[i] = "0123456789ABCDEF"[val % base];

        puts(&buf[i+1]);
    }

}