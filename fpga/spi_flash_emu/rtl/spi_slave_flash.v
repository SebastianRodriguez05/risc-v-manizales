// Emulador simple de flash SPI (solo comando READ 0x03) respaldado en BRAM.
// Modo SPI 0 (CPOL=0, CPHA=0): MOSI se muestrea en flanco de SUBIDA de SCK,
// MISO se actualiza en flanco de BAJADA de SCK.
module spi_slave_flash #(
    parameter MEM_BYTES  = 8192,        // 8 KB
    parameter ADDR_WIDTH = 13,          // bits para direccionar MEM_BYTES (2^13 = 8192)
    parameter MEM_INIT   = "mem_init.hex"
)(
    input  wire CS_N,   // chip select, activo en bajo
    input  wire SCK,    // reloj SPI (lo genera el maestro)
    input  wire MOSI,   // maestro -> esclavo
    output reg  MISO    // esclavo -> maestro
);

    localparam CMD_READ = 8'h03;

    // Memoria (se sintetiza como BRAM)
    reg [7:0] mem [0:MEM_BYTES-1];
    initial if (MEM_INIT != "") $readmemh(MEM_INIT, mem);

    // ---- Recepción: comando (8b) + dirección (24b) en flanco de SUBIDA ----
    reg [5:0]  rx_cnt;      // 0..32
    reg [7:0]  cmd_sr;
    reg [23:0] addr_sr;

    always @(posedge SCK or posedge CS_N) begin
        if (CS_N) begin
            rx_cnt  <= 6'd0;
            cmd_sr  <= 8'd0;
            addr_sr <= 24'd0;
        end else if (rx_cnt < 32) begin
            if (rx_cnt < 8)
                cmd_sr  <= {cmd_sr[6:0],   MOSI};
            else
                addr_sr <= {addr_sr[22:0], MOSI};
            rx_cnt <= rx_cnt + 6'd1;
        end
    end

    wire addr_ready = (rx_cnt >= 32);
    wire cmd_ok     = (cmd_sr == CMD_READ);

    // ---- Transmisión: byte de datos en flanco de BAJADA ----
    reg [ADDR_WIDTH-1:0] tx_addr;
    reg [2:0]            tx_bit;     // 7 downto 0
    reg                  tx_started;

    always @(negedge SCK or posedge CS_N) begin
        if (CS_N) begin
            tx_addr    <= {ADDR_WIDTH{1'b0}};
            tx_bit     <= 3'd7;
            tx_started <= 1'b0;
            MISO       <= 1'b0;
        end else if (addr_ready && cmd_ok) begin
            if (!tx_started) begin
                // primer byte: cargar direccion recibida y sacar su MSB
                tx_addr    <= addr_sr[ADDR_WIDTH-1:0];
                tx_bit     <= 3'd7;
                tx_started <= 1'b1;
                MISO       <= mem[addr_sr[ADDR_WIDTH-1:0]][7];
            end else if (tx_bit == 3'd0) begin
                // fin de byte: pasar al siguiente (lectura continua)
                tx_addr <= tx_addr + 1'b1;
                tx_bit  <= 3'd7;
                MISO    <= mem[tx_addr + 1'b1][7];
            end else begin
                tx_bit <= tx_bit - 3'd1;
                MISO   <= mem[tx_addr][tx_bit - 3'd1];
            end
        end
    end

endmodule