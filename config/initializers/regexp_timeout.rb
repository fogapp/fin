# Limit regex backtracking to prevent ReDoS from user-supplied patterns
# (rule conditions, merchant rule patterns). Ruby 3.2+.
Regexp.timeout = 1.0
