# Mutable candidate for the Alice Gutenberg problem.
# The fixed evaluator owns data prep, time budget, evaluation, and result logging.

LEARNING_RATE=0.0003
WEIGHT_DECAY=0.0

MAX_SEQ_LEN=128
DEVICE_BATCH_SIZE=4
TOTAL_BATCH_SIZE=512

MLX_LAYERS=1
MLX_DIM=32
MLX_HEADS=4
MLX_MLP_DIM=64
