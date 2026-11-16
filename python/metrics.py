"""metrics.py -- prediction accuracy, misprediction rate, CPI and speedup.

Owner: Sarvesh  |  Project 5: Dynamic Branch Prediction Unit

CPI model (assumptions are parameters):
    CPI = base_CPI + branch_freq * mispredict_rate * mispredict_penalty
"""

BASE_CPI = 1.0
BRANCH_FREQ = 0.2
PENALTY = 2


def accuracy(correct, branches):
    """Fraction of branches whose direction was predicted correctly (%)."""
    return 100.0 * correct / branches if branches else 0.0


def mispredict_rate(mispredictions, branches):
    """Fraction of branches that caused a pipeline flush (0..1)."""
    return mispredictions / branches if branches else 0.0


def cpi(mispredictions, branches, base_cpi=BASE_CPI, branch_freq=BRANCH_FREQ, penalty=PENALTY):
    return base_cpi + branch_freq * mispredict_rate(mispredictions, branches) * penalty


def speedup(cpi_baseline, cpi_scheme):
    """Speedup of a scheme over the baseline for the same instruction count."""
    return cpi_baseline / cpi_scheme


if __name__ == "__main__":
    # small self-test with hand-computed values
    assert abs(cpi(11, 100) - 1.044) < 1e-12
    assert abs(cpi(90, 100) - 1.36) < 1e-12
    assert abs(speedup(1.36, 1.044) - 1.3027) < 1e-4
    assert accuracy(89, 100) == 89.0
    print("metrics.py self-test passed")
