catch {unset env(PYTHONHOME)}
catch {unset env(PYTHONPATH)}
puts [exec python ./python/pipeline_2ctx_model.py --width 32 --height 24 --max-iter 64 --center -0.5 0.0 --step 0.02 --pixels 512]
