from dataclasses import dataclass


@dataclass
class OcrPoint:
    x: float
    y: float

    def __post_init__(self):
        self.x = float(self.x)


o = OcrPoint(x="123", y="456")
print(o)
