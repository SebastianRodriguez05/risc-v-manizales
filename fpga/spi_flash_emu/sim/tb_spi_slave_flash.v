`timescale 1ns/1ps

module tb_spi_slave_flash;

    parameter MEM_BYTES  = 8192;
    localparam TEST_BYTES = 1120;

    reg  CS_N = 1'b1;
    reg  SCK  = 1'b0;
    reg  MOSI = 1'b0;
    wire MISO;

    localparam SCK_HALF = 50;

    spi_slave_flash #(
        .MEM_BYTES  (MEM_BYTES),
        .ADDR_WIDTH (13),
        .MEM_INIT   ("mem_init.hex")
    ) dut (
        .CS_N (CS_N),
        .SCK  (SCK),
        .MOSI (MOSI),
        .MISO (MISO)
    );

    // Referencia: mismo archivo que carga el DUT, para comparar automaticamente
    reg [7:0] expected [0:MEM_BYTES-1];
    initial $readmemh("mem_init.hex", expected);

    task spi_send_bit(input bit_val);
        begin
            MOSI = bit_val;
            #SCK_HALF SCK = 1'b1;
            #SCK_HALF SCK = 1'b0;
        end
    endtask

    reg [7:0] rx_byte;

    task spi_read_bit;
        begin
            #SCK_HALF SCK = 1'b1;
            rx_byte = {rx_byte[6:0], MISO};
            #SCK_HALF SCK = 1'b0;
        end
    endtask

    integer i;
    reg [31:0] cmd_addr;
    integer errors;

    initial begin
        $dumpfile("tb_spi_slave_flash.vcd");
        $dumpvars(0, tb_spi_slave_flash);

        CS_N = 1'b1; SCK = 1'b0; MOSI = 1'b0;
        #200;

        CS_N = 1'b0;
        #20;

        cmd_addr = {8'h03, 24'h000000};
        for (i = 31; i >= 0; i = i - 1)
            spi_send_bit(cmd_addr[i]);

        errors = 0;
        for (i = 0; i < TEST_BYTES; i = i + 1) begin
            rx_byte = 8'h00;
            repeat (8) spi_read_bit;
            if (rx_byte !== expected[i]) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("[ERR] byte %0d = 0x%02h (se esperaba 0x%02h)", i, rx_byte, expected[i]);
            end
        end

        CS_N = 1'b1;
        #100;

        if (errors == 0)
            $display("RESULTADO: %0d/%0d bytes correctos -> OK", TEST_BYTES, TEST_BYTES);
        else
            $display("RESULTADO: %0d errores de %0d bytes -> FALLO", errors, TEST_BYTES);

        $display("Simulacion terminada.");
        $finish;
    end

endmodule
