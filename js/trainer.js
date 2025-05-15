import { parseUInt24 } from './uint24.js';

export class Trainer {
  constructor() {
    this.device = null;
    this.server = null;
    this.controlPoint = null;
    this.dataChar = null;

    this.power = 0;
    this.cadence = 0;
    this.speed = 0;

    this._onDataCallback = null;
  }

  async connect() {
    const device = await navigator.bluetooth.requestDevice({
      filters: [{ services: ['fitness_machine'] }]
    });

    this.device = device;
    this.server = await device.gatt.connect();
    this.service = await this.server.getPrimaryService('fitness_machine');

    const dataChar = await this.service.getCharacteristic('indoor_bike_data');
    await dataChar.startNotifications();
    dataChar.addEventListener('characteristicvaluechanged', this._handleBikeData.bind(this));

    const controlPoint = await this.service.getCharacteristic('fitness_machine_control_point');
    this.controlPoint = controlPoint; // save it
    await controlPoint.startNotifications();
    controlPoint.addEventListener('characteristicvaluechanged', this._handleControlResponse.bind(this));

    await this._requestControl(); // Write 0x00 (request control)
  }

  _handleControlResponse(event) {
    const value = event.target.value;
    const opcode = value.getUint8(0);
    const response = value.getUint8(1);
  }


  async _requestControl() {
    if (!this.controlPoint) return;

    const REQUEST_CONTROL = 0x00;
    const buffer = Uint8Array.of(REQUEST_CONTROL);
    await this.controlPoint.writeValue(buffer);
  }

  async setTargetPower(watts) {
    const SET_TARGET_POWER = new Uint8Array([
      0x05,
      watts & 0xff,
      (watts >> 8) & 0xff
    ]);
    await this.controlPoint.writeValueWithResponse(SET_TARGET_POWER);
  }

  onData(callback) {
    this._onDataCallback = callback;
  }

  _handleBikeData(event) {
    const message = new Uint8Array(event.target.value.buffer);

    const flag_more_data = !(message[0] & 0b00000001);
    const flag_average_speed = !!(message[0] & 0b00000010);
    const flag_instantaneous_cadence = !!(message[0] & 0b00000100);
    const flag_average_cadence = !!(message[0] & 0b00001000);
    const flag_total_distance = !!(message[0] & 0b00010000);
    const flag_resistance_level = !!(message[0] & 0b00100000);
    const flag_instantaneous_power = !!(message[0] & 0b01000000);
    const flag_average_power = !!(message[0] & 0b10000000);
    const flag_expended_energy = !!(message[1] & 0b00000001);
    const flag_heart_rate = !!(message[1] & 0b00000010);
    const flag_metabolic_equivalent = !!(message[1] & 0b00000100);
    const flag_elapsed_time = !!(message[1] & 0b00001000);
    const flag_remaining_time = !!(message[1] & 0b00010000);

    let i = 2;

    if (flag_more_data) {
      this.speed = (message[i] | (message[i + 1] << 8)) / 100;
      i += 2;
    }
    if (flag_average_speed) i += 2;
    if (flag_instantaneous_cadence) {
      this.cadence = (message[i] | (message[i + 1] << 8)) / 2;
      i += 2;
    }
    if (flag_average_cadence) i += 2;
    if (flag_total_distance) i += 3;
    if (flag_resistance_level) i += 2;
    if (flag_instantaneous_power) {
      this.power = (message[i] | (message[i + 1] << 8)) << 16 >> 16;
      i += 2;
    }
    if (flag_average_power) i += 2;
    if (flag_expended_energy) i += 5;
    if (flag_heart_rate) i += 1;
    if (flag_metabolic_equivalent) i += 1;
    if (flag_elapsed_time) i += 2;
    if (flag_remaining_time) i += 2;

    if (this._onDataCallback) {
      this._onDataCallback({
        power: this.power,
        cadence: this.cadence,
        speed: this.speed
      });
    }
  }
}
