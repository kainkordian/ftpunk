export class RampTest {
  constructor(trainer, hrm, ui, isHeavyRider = true, warmupDuration = 600, warmupWatts) {
    this.trainer = trainer;
    this.hrm = hrm;
    this.ui = ui;
    this.elapsed = 0;
    this.interval = null;
    this.isHeavyRider = isHeavyRider;
    this.warmupSeconds = warmupDuration;
    this.warmupWatts = warmupWatts;
    this.stageWatts = this.isHeavyRider ? 100 : 50;
    this.stageDuration = this.isHeavyRider ? 12 : 20;
    this.cooldownWatts = this.isHeavyRider ? 75 : 50;
    this.powerHistory = [];
    this.testStarted = false;
  }

  async start() {
    this.ui.setBackground('');
    this.ui.showRestart();
    this.ui.showMessage('Warming up... Start pedaling');

    await this._waitForPedalStart();
    console.log("started pedaling")
    await this.trainer.setTargetPower(this.warmupWatts);
    this.testStarted = true;

    this.interval = setInterval(() => {
      this.elapsed++;

      const rampStarted = this.elapsed >= this.warmupSeconds;


      if (!rampStarted) {
        const timeLeft = this.warmupSeconds - this.elapsed;
        this.ui.showMessage(`Ramp starts in: ${this.ui._formatTime(timeLeft)}`);
        this.ui.update(this.trainer.power, this.trainer.cadence, this.trainer.speed, this.hrm.heartRate, timeLeft, this.warmupWatts);
      } else {
        const rampElapsed = this.elapsed - this.warmupSeconds;
        this.ui.update(this.trainer.power, this.trainer.cadence, this.trainer.speed, this.hrm.heartRate, rampElapsed, this.stageWatts);

        if (rampElapsed === 0) {
          this.ui.showMessage('Ramp test started!');
          this.trainer.setTargetPower(this.stageWatts);
        }

        if (rampElapsed > 0 && rampElapsed % this.stageDuration === 0) {
          this.stageWatts += 5;
          this.trainer.setTargetPower(this.stageWatts);
        }

        if (this.trainer.cadence < 20) {
          this._finishTest();
        }

        this.powerHistory.push(this.trainer.power);
      }      
    }, 1000);
  }

  async _waitForPedalStart() {
    while (this.trainer.cadence < 20) {
      await new Promise(res => setTimeout(res, 500));
    }
  }

  _finishTest() {
    clearInterval(this.interval);
    const last60 = this.powerHistory.slice(-60);
    const avg = last60.reduce((a, b) => a + b, 0) / last60.length;
    const minFtp = Math.floor(avg * 0.72);
    const maxFtp = Math.floor(avg * 0.77);
    this.ui.showFTP(minFtp, maxFtp, Math.floor(avg));
    this.ui.setBackground('done');
    this.trainer.setTargetPower(this.cooldownWatts);
    this.ui.update(this.trainer.power, this.trainer.cadence, this.trainer.speed, this.hrm.heartRate, 0, this.cooldownWatts);
  }
}