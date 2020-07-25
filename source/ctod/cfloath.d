module ctod.cfloath;

/// Params:
///   str = macro from <float.h>
/// Returns: corresponding D type property, or `null` if no match
string transaleLimit(string str) {
	switch (str) {
		//case "FLT_EVAL_METHOD": return "";
		//case "FLT_ROUNDS": return "";
		//case "FLT_RADIX": return "";
		case "FLT_MANT_DIG": return "float.mant_dig";
		case "DBL_MANT_DIG": return "double.mant_dig";
		case "LDBL_MANT_DIG": return "real.mant_dig";
		//case "DECIMAL_DIG": return "";
		case "FLT_DIG": return "float.dig";
		case "DBL_DIG": return "double.dig";
		case "LDBL_DIG": return "real.dig";
		case "FLT_MIN_EXP": return "float.min_exp";
		case "DBL_MIN_EXP": return "double.min_exp";
		case "LDBL_MIN_EXP": return "real.min_exp";
		case "FLT_MIN_10_EXP": return "float.min_10_exp";
		case "DBL_MIN_10_EXP": return "double.min_10_exp";
		case "LDBL_MIN_10_EXP": return "real.min_10_exp";
		case "FLT_MAX_EXP": return "float.max_exp";
		case "DBL_MAX_EXP": return "double.max_exp";
		case "LDBL_MAX_EXP": return "real.max_exp";
		case "FLT_MAX_10_EXP": return "float.max_10_exp";
		case "DBL_MAX_10_EXP": return "double.max_10_exp";
		case "LDBL_MAX_10_EXP": return "real.max_10_exp";
		case "FLT_MAX":  return "float.max";
		case "DBL_MAX":  return "double.max";
		case "LDBL_MAX": return "real.max";
		case "FLT_EPSILON": return "float.epsilon";
		case "DBL_EPSILON": return "double.epsilon";
		case "LDBL_EPSILON": return "real.epsilon";
		case "FLT_MIN":  return "float.min";
		case "DBL_MIN":  return "double.min";
		case "LDBL_MIN": return "real.min";
		default: return null;
	}
}