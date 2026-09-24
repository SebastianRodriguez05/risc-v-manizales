module top (
    input  wire clk,
    output wire led_heartbeat,  // parpadea siempre: confirma que el bitstream corre
    output wire led_cs,         // se enciende (activo bajo) durante una transaccion SPI
    input  wire CS_N,
    input  wire SCK,
    input  wire MOSI,
    output wire MISO
);

    reg [24:0] counter;
    always @(posedge clk) counter <= counter + 1'b1;

    assign led_heartbeat = ~counter[24]; // logica activa en bajo, igual que tus otros proyectos

    spi_slave_flash #(
        .MEM_BYTES  (8192),
        .ADDR_WIDTH (13),
        .MEM_INIT   ("rtl/mem_init.hex")
    ) flash_inst (
        .CS_N (CS_N),
        .SCK  (SCK),
        .MOSI (MOSI),
        .MISO (MISO)
    );

    assign led_cs = CS_N; // activo bajo: se enciende mientras dura una transaccion

endmodule