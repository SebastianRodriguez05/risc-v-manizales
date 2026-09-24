module led(
    input  Clock,
    output IO_voltage
);

/********** Contador **********/
parameter count_value = 13_499_999; // pulsos para 0.5s a 27MHz

reg [23:0] count_value_reg;
reg        count_value_flag;

always @(posedge Clock) begin
    if (count_value_reg <= count_value) begin
        count_value_reg  <= count_value_reg + 1'b1;
        count_value_flag <= 1'b0;
    end else begin
        count_value_reg  <= 24'b0;
        count_value_flag <= 1'b1;
    end
end

/********** Cambio de estado del LED **********/
reg IO_voltage_reg = 1'b0;

always @(posedge Clock) begin
    if (count_value_flag)
        IO_voltage_reg <= ~IO_voltage_reg;
    else
        IO_voltage_reg <= IO_voltage_reg;
end

assign IO_voltage = IO_voltage_reg;

endmodule