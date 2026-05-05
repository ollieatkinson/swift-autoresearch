# Mutable candidate for the Tiny Lab Notes smoke problem.
# This starts intentionally conservative so a simple learning-rate edit can improve it.

LEARNING_RATE=0.0001
WEIGHT_DECAY=0.0

MAX_SEQ_LEN=128
DEVICE_BATCH_SIZE=4
TOTAL_BATCH_SIZE=512

MLX_LAYERS=1
MLX_DIM=32
MLX_HEADS=4
MLX_MLP_DIM=64
